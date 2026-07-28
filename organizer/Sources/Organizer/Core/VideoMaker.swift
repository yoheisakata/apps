import Foundation
import AppKit

enum DurationMode { case clip, total }

struct VideoMakerConfig {
    var videos: [URL]
    var titleText: String
    var musicPath: String
    var outputPath: String
    var durationMode: DurationMode
    var clipSec: Int
    var totalSec: Int
    var offsetSec: Int
    var bgmVolume: Double
    var origVolume: Double
    var transitionSec: Double
    var qualityPreset: Int
}

enum VideoMakerError: Error, LocalizedError {
    case ffmpegMissing
    case noVideos
    case ffmpegFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing: return "ffmpeg が見つかりません。brew install ffmpeg でインストールしてください"
        case .noVideos: return "動画が選択されていません"
        case .ffmpegFailed(let tail): return "ffmpeg 失敗:\n\(tail)"
        }
    }
}

/// 旧omoideアプリの移植。子ども動画のフォルダから短いクリップを抜き出してつなぎ、
/// タイトルカード・BGMを合成したまとめ動画を作る。「まとめ動画」ペイン用。
enum VideoMaker {
    static let videoExtensions: Set<String> = ["mp4", "mov", "avi", "m4v", "mkv", "mts", "m2ts", "3gp"]

    static func findVideos(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
    }

    /// フォルダ名から「YYYY年MM月」のような構造を検出してタイトルの初期値にする(例: .../2024/03 → March, 2024)。
    static func detectTitle(from path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        let last = parts.last ?? ""
        let secondLast = parts.dropLast().last ?? ""
        let months = ["01": "January", "02": "February", "03": "March", "04": "April",
                      "05": "May", "06": "June", "07": "July", "08": "August",
                      "09": "September", "10": "October", "11": "November", "12": "December"]
        if let monthName = months[last], secondLast.count == 4, Int(secondLast) != nil {
            return "\(monthName), \(secondLast)"
        }
        if last.count == 4, Int(last) != nil { return last }
        return ""
    }

    // MARK: - 生成処理

    static func generate(
        config: VideoMakerConfig,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void,
        setDetail: @escaping (String) -> Void,
        onCancel: (@escaping () -> Void) -> Void,
        checkCancel: () throws -> Void
    ) async throws {
        guard !config.videos.isEmpty else { throw VideoMakerError.noVideos }
        guard let ffmpeg = ToolLocator.resolve("ffmpeg"), let ffprobe = ToolLocator.resolve("ffprobe") else {
            throw VideoMakerError.ffmpegMissing
        }

        let tmpDir = URL(fileURLWithPath: config.outputPath)
            .deletingLastPathComponent()
            .appendingPathComponent(".video_tmp_\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let effectiveClipSec: Double = config.durationMode == .total
            ? Double(config.totalSec) / Double(config.videos.count)
            : Double(config.clipSec)

        progress("対象動画: \(config.videos.count) 本, 1本あたり約 \(String(format: "%.1f", effectiveClipSec)) 秒")

        // フェーズ: クリップ抽出 0〜80%, 結合 80〜85%, フェード/タイトル 85〜93%, BGM 93〜100%
        let total = config.videos.count
        var clipFiles: [URL] = []
        for (idx, vpath) in config.videos.enumerated() {
            try checkCancel()
            setProgress(Double(idx) / Double(total) * 0.8)
            setDetail("クリップ抽出中… \(idx + 1)/\(total): \(vpath.lastPathComponent)")
            progress("[\(idx + 1)/\(total)] \(vpath.lastPathComponent)")

            let dur = getDuration(ffprobe: ffprobe, path: vpath.path) ?? 0
            let offset = Double(config.offsetSec)
            let latest = dur > effectiveClipSec + offset ? dur - effectiveClipSec : 0
            let earliest = min(offset, latest)

            // 最大5回リトライして暗い/止まったシーンを避ける
            var goodStart: Double = earliest
            for attempt in 0..<5 {
                let candidate = latest > earliest
                    ? Double.random(in: earliest...latest)
                    : earliest
                if isGoodClip(ffmpeg: ffmpeg, path: vpath.path, start: candidate, duration: effectiveClipSec) {
                    goodStart = candidate
                    break
                }
                if attempt == 4 { goodStart = candidate } // 最終はあきらめて使う
            }

            let outClip = tmpDir.appendingPathComponent(String(format: "clip_%04d.mp4", idx))
            // fps・解像度を統一(縦動画はピラーボックスで1920x1080に収める)
            let normalizeFilter = "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p"
            try await runFFmpeg(ffmpeg, [
                "-y", "-ss", String(goodStart), "-i", vpath.path,
                "-t", String(effectiveClipSec),
                "-vf", normalizeFilter,
                "-af", "volume=\(config.origVolume),aresample=44100,aformat=channel_layouts=stereo",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-ar", "44100",
                "-movflags", "+faststart",
                outClip.path,
            ], onCancel: onCancel)
            clipFiles.append(outClip)
        }

        try checkCancel()

        // クリップを結合(ディゾルブトランジション付き)
        let concatOut = tmpDir.appendingPathComponent("concat.mp4")
        let clipCount = clipFiles.count
        let transDur = min(config.transitionSec, effectiveClipSec / 2)

        if clipCount == 1 {
            try FileManager.default.copyItem(at: clipFiles[0], to: concatOut)
        } else if transDur <= 0 {
            let concatDurTotal = Double(clipCount) * effectiveClipSec
            let listFile = tmpDir.appendingPathComponent("clips.txt")
            let listContent = clipFiles.map { "file '\($0.path)'" }.joined(separator: "\n")
            try listContent.write(to: listFile, atomically: true, encoding: .utf8)
            setDetail("クリップを結合中…")
            try await runFFmpegWithProgress(ffmpeg, [
                "-y", "-f", "concat", "-safe", "0",
                "-i", listFile.path, "-c", "copy", concatOut.path,
            ], totalSec: concatDurTotal, baseProgress: 0.8, rangeProgress: 0.05, setProgress: setProgress, onCancel: onCancel)
        } else {
            var args: [String] = ["-y"]
            for clip in clipFiles {
                args += ["-i", clip.path]
            }
            var vf = ""
            var af = ""
            for i in 0..<(clipCount - 1) {
                let offset = Double(i + 1) * effectiveClipSec - Double(i + 1) * transDur
                let vIn = i == 0 ? "[0:v]" : "[v\(i)]"
                let aIn = i == 0 ? "[0:a]" : "[a\(i)]"
                let vOut = i == clipCount - 2 ? "[vout]" : "[v\(i + 1)]"
                let aOut = i == clipCount - 2 ? "[aout]" : "[a\(i + 1)]"
                vf += "\(vIn)[\(i + 1):v]xfade=transition=fade:duration=\(String(format: "%.3f", transDur)):offset=\(String(format: "%.3f", offset))\(vOut);"
                af += "\(aIn)[\(i + 1):a]acrossfade=d=\(String(format: "%.3f", transDur)):c1=tri:c2=tri\(aOut);"
            }
            let filterComplex = String((vf + af).dropLast())
            args += ["-filter_complex", filterComplex]
            args += ["-map", "[vout]", "-map", "[aout]"]
            args += ["-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset)]
            args += ["-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2"]
            args += [concatOut.path]
            let concatDurTotal = Double(clipCount) * effectiveClipSec - Double(clipCount - 1) * transDur
            setDetail("ディゾルブで結合中…")
            try await runFFmpegWithProgress(ffmpeg, args, totalSec: concatDurTotal, baseProgress: 0.8, rangeProgress: 0.05, setProgress: setProgress, onCancel: onCancel)
        }

        try checkCancel()

        // ── フェード+タイトルオーバーレイを全体に適用 ──
        let estimatedDur = Double(clipCount) * effectiveClipSec - Double(max(0, clipCount - 1)) * min(config.transitionSec, effectiveClipSec / 2)
        let totalDur = getDuration(ffprobe: ffprobe, path: concatOut.path) ?? estimatedDur
        let fadeSec = min(1.0, totalDur / 6)
        let fadeOutSt = max(0, totalDur - fadeSec)
        let fadedOut = tmpDir.appendingPathComponent("faded.mp4")
        setProgress(0.85)
        setDetail("フェード・タイトルを適用中…")

        let title = config.titleText

        if !title.isEmpty {
            let overlayPng = tmpDir.appendingPathComponent("overlay.png")
            renderTitleOverlay(text: title, fontSize: 36, width: 1920, height: 1080, position: .topLeft, to: overlayPng)
            try await runFFmpeg(ffmpeg, [
                "-y", "-i", concatOut.path, "-i", overlayPng.path,
                "-filter_complex", "[0:v][1:v]overlay=0:0,fade=t=in:st=0:d=\(String(format: "%.3f", fadeSec)),fade=t=out:st=\(String(format: "%.3f", fadeOutSt)):d=\(String(format: "%.3f", fadeSec))",
                "-af", "afade=t=in:st=0:d=\(String(format: "%.3f", fadeSec)),afade=t=out:st=\(String(format: "%.3f", fadeOutSt)):d=\(String(format: "%.3f", fadeSec))",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                fadedOut.path,
            ], onCancel: onCancel)
        } else {
            try await runFFmpeg(ffmpeg, [
                "-y", "-i", concatOut.path,
                "-vf", "fade=t=in:st=0:d=\(String(format: "%.3f", fadeSec)),fade=t=out:st=\(String(format: "%.3f", fadeOutSt)):d=\(String(format: "%.3f", fadeSec))",
                "-af", "afade=t=in:st=0:d=\(String(format: "%.3f", fadeSec)),afade=t=out:st=\(String(format: "%.3f", fadeOutSt)):d=\(String(format: "%.3f", fadeSec))",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                fadedOut.path,
            ], onCancel: onCancel)
        }

        try checkCancel()

        // ── タイトルカード(黒画面+中央タイトル)を先頭に追加 ──
        let withTitle: URL
        if !title.isEmpty {
            let cardDur = 3.0
            let cardFade = 0.5
            let titleCard = tmpDir.appendingPathComponent("titlecard.mp4")
            let titleCardPng = tmpDir.appendingPathComponent("titlecard.png")
            setProgress(0.87)
            setDetail("タイトルカードを作成中…")
            renderTitleOverlay(text: title, fontSize: 80, width: 1920, height: 1080, position: .center, to: titleCardPng)
            try await runFFmpeg(ffmpeg, [
                "-y",
                "-loop", "1", "-i", titleCardPng.path,
                "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                "-t", String(cardDur),
                "-vf", "fps=30,fade=t=in:st=0:d=\(cardFade),fade=t=out:st=\(cardDur - cardFade):d=\(cardFade)",
                "-af", "afade=t=in:st=0:d=\(cardFade),afade=t=out:st=\(cardDur - cardFade):d=\(cardFade)",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
                "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                titleCard.path,
            ], onCancel: onCancel)
            let cardListFile = tmpDir.appendingPathComponent("card_list.txt")
            try "file '\(titleCard.path)'\nfile '\(fadedOut.path)'".write(to: cardListFile, atomically: true, encoding: .utf8)
            let titledOut = tmpDir.appendingPathComponent("titled.mp4")
            try await runFFmpeg(ffmpeg, [
                "-y", "-f", "concat", "-safe", "0",
                "-i", cardListFile.path, "-c", "copy", titledOut.path,
            ], onCancel: onCancel)
            withTitle = titledOut
        } else {
            withTitle = fadedOut
        }

        try checkCancel()

        // ── BGM合成 ──
        let finalDur = getDuration(ffprobe: ffprobe, path: withTitle.path) ?? totalDur
        if !config.musicPath.isEmpty, FileManager.default.fileExists(atPath: config.musicPath) {
            // BGMをループ→finalDurに切り詰め→フェード適用→一時ファイルへ
            let bgmFadeDur = min(2.0, finalDur / 4)
            let bgmFadeOutSt = max(0, finalDur - bgmFadeDur)
            let bgmReady = tmpDir.appendingPathComponent("bgm_ready.aac")
            setDetail("BGMを準備中…")
            try await runFFmpeg(ffmpeg, [
                "-y",
                "-stream_loop", "-1", "-i", config.musicPath,
                "-t", String(format: "%.3f", finalDur),
                "-af", "volume=\(config.bgmVolume),afade=t=in:st=0:d=\(bgmFadeDur),afade=t=out:st=\(String(format: "%.3f", bgmFadeOutSt)):d=\(bgmFadeDur)",
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                bgmReady.path,
            ], onCancel: onCancel)
            setProgress(0.93)
            setDetail("BGMを合成中…")
            try await runFFmpegWithProgress(ffmpeg, [
                "-y",
                "-i", withTitle.path,
                "-i", bgmReady.path,
                "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=first[aout]",
                "-map", "0:v", "-map", "[aout]",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                "-t", String(format: "%.3f", finalDur),
                config.outputPath,
            ], totalSec: finalDur, baseProgress: 0.93, rangeProgress: 0.07, setProgress: setProgress, onCancel: onCancel)
        } else {
            try FileManager.default.copyItem(atPath: withTitle.path, toPath: config.outputPath)
        }

        setProgress(1.0)
        progress("\n完成: \(config.outputPath)")
    }

    // MARK: - タイトル画像生成(drawtextの代替)

    private enum TitlePosition { case topLeft, center }

    private static func renderTitleOverlay(text: String, fontSize: CGFloat, width: Int, height: Int, position: TitlePosition, to url: URL) {
        let size = CGSize(width: width, height: height)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

        if position == .center {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        }

        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(position == .topLeft ? 0.85 : 1.0)
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let x: CGFloat
        let y: CGFloat
        switch position {
        case .topLeft:
            let padX: CGFloat = 24
            let padY: CGFloat = 24
            let boxPad: CGFloat = 8
            let boxRect = CGRect(x: padX - boxPad,
                                 y: CGFloat(height) - padY - bounds.height - boxPad,
                                 width: bounds.width + boxPad * 2,
                                 height: bounds.height + boxPad * 2)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
            ctx.fill(boxRect)
            x = padX
            y = padY
        case .center:
            x = (CGFloat(width) - bounds.width) / 2
            y = (CGFloat(height) - bounds.height) / 2
        }

        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)

        guard let image = ctx.makeImage() else { return }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: - クリップ品質チェック

    /// true = 使えるクリップ(暗すぎず、止まっていない)
    private static func isGoodClip(ffmpeg: String, path: String, start: Double, duration: Double) -> Bool {
        let result = try? SyncExec.run(ffmpeg, [
            "-ss", String(start),
            "-i", path,
            "-t", String(min(duration, 3.0)), // 最初の3秒だけチェック
            "-vf", "blackdetect=d=0.5:pix_th=0.10,freezedetect=n=-60dB:d=0.5",
            "-an", "-f", "null", "-",
        ])
        guard let output = result else { return true }
        // black_start や freeze_start が出てきたらNG
        let isBad = output.contains("black_start") || output.contains("freeze_start")
        return !isBad
    }

    private static func getDuration(ffprobe: String, path: String) -> Double? {
        guard let output = try? SyncExec.run(ffprobe, [
            "-v", "quiet", "-print_format", "json", "-show_format", path,
        ]) else { return nil }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fmt = json["format"] as? [String: Any],
              let durStr = fmt["duration"] as? String else { return nil }
        return Double(durStr)
    }

    // MARK: - ffmpeg実行ヘルパー

    /// 進捗を追わない単発呼び出し(クリップ抽出・タイトル合成等)。進捗はインデックス/固定値で呼び出し側が管理する。
    private static func runFFmpeg(_ ffmpeg: String, _ args: [String], onCancel: (@escaping () -> Void) -> Void) async throws {
        let runner = ProcessRunner()
        onCancel { runner.cancel() }
        var errorTail: [String] = []
        let exitCode = try await runner.run(ffmpeg, args) { line in
            errorTail.append(line)
            if errorTail.count > 20 { errorTail.removeFirst() }
        }
        if exitCode != 0 {
            throw VideoMakerError.ffmpegFailed(errorTail.suffix(10).joined(separator: "\n"))
        }
    }

    /// `-progress pipe:1`の`out_time_ms`を読み、`baseProgress`〜`baseProgress+rangeProgress`の範囲に写像する
    /// (結合・BGM合成など、実時間がかかる呼び出し用)。
    private static func runFFmpegWithProgress(
        _ ffmpeg: String, _ args: [String],
        totalSec: Double, baseProgress: Double, rangeProgress: Double,
        setProgress: @escaping (Double?) -> Void,
        onCancel: (@escaping () -> Void) -> Void
    ) async throws {
        let runner = ProcessRunner()
        onCancel { runner.cancel() }
        var errorTail: [String] = []
        let exitCode = try await runner.run(ffmpeg, args + ["-progress", "pipe:1", "-nostats"]) { line in
            if line.hasPrefix("out_time_ms="), let ms = Double(line.dropFirst("out_time_ms=".count)), ms > 0, totalSec > 0 {
                let frac = min(ms / 1_000_000 / totalSec, 1.0)
                setProgress(baseProgress + frac * rangeProgress)
            } else if line.hasPrefix("progress=end") {
                setProgress(baseProgress + rangeProgress)
            } else {
                errorTail.append(line)
                if errorTail.count > 20 { errorTail.removeFirst() }
            }
        }
        if exitCode != 0 {
            throw VideoMakerError.ffmpegFailed(errorTail.suffix(10).joined(separator: "\n"))
        }
        setProgress(baseProgress + rangeProgress)
    }
}
