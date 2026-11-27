import Foundation
import AppKit

struct VideoMakerConfig {
    var videos: [URL]
    var titleText: String
    var musicPath: String
    var outputPath: String
    var clipSec: Int
    var offsetSec: Int
    var bgmVolume: Double
    var origVolume: Double
    var transitionSec: Double
    var qualityPreset: Int
    /// 自動モード用: `videos`と同じ順序・個数で各クリップの秒数を個別に指定する(2秒/3秒混在)。
    /// nilの場合は従来通り全クリップに`clipSec`を一律適用する(手動モード)。
    var perClipSeconds: [Int]? = nil
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
    /// タイトルカード(黒画面+中央タイトル)の長さ。`generate(config:)`と`estimateTotalSec(config:)`で共有する。
    static let titleCardDurationSec = 3.0
    /// 末尾に追加する無音の黒みの長さ。`generate(config:)`と`estimateTotalSec(config:)`で共有する。
    static let blackHoldSec = 2.0

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

    /// 任意の音声/動画ファイルの長さ(秒)をffprobeで取得する。BGMファイルの長さ表示等、
    /// 生成処理の外(UI表示用)から呼ぶための公開版。
    static func mediaDurationSec(_ path: String) -> Double? {
        guard let ffprobe = ToolLocator.resolve("ffprobe") else { return nil }
        return getDuration(ffprobe: ffprobe, path: path)
    }

    /// UIでのプレビュー表示用に、`generate(config:)`と同じ計算式で最終的な動画の長さを見積もる
    /// (クリップ抽出秒数の合計 − トランジションの重なり分 + タイトルカード + 末尾の黒み)。
    /// フェード自体は既存区間内で行うため長さには影響しない。
    static func estimateTotalSec(config: VideoMakerConfig) -> Double {
        guard !config.videos.isEmpty else { return 0 }
        let durations = clipDurations(config: config)
        let mainDur = mainDuration(durations: durations, transitionSec: config.transitionSec)
        let titleCardDur = config.titleText.isEmpty ? 0.0 : titleCardDurationSec
        return max(0, mainDur) + titleCardDur + blackHoldSec
    }

    /// `config.videos`と対応する各クリップの秒数。自動モード(`perClipSeconds`あり)ならそれを、
    /// 手動モードなら`clipSec`を全クリップに一律適用したものを返す。
    private static func clipDurations(config: VideoMakerConfig) -> [Double] {
        if let per = config.perClipSeconds, per.count == config.videos.count {
            return per.map(Double.init)
        }
        return Array(repeating: Double(config.clipSec), count: config.videos.count)
    }

    /// クリップ秒数の配列から、隣接ペアごとのディゾルブ重なり(お互いの短い方の半分を上限)を
    /// 差し引いた結合後の実長を計算する。自動モードのようにクリップごとに秒数が異なっていても、
    /// `generate(config:)`側のxfade結合ロジックと同じ結果になるよう共通化している。
    private static func mainDuration(durations: [Double], transitionSec: Double) -> Double {
        guard !durations.isEmpty else { return 0 }
        var total = durations[0]
        for i in 1..<durations.count {
            let transDur = transitionSec > 0 ? min(transitionSec, min(durations[i - 1], durations[i]) / 2) : 0
            total += durations[i] - transDur
        }
        return total
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

        var durations = clipDurations(config: config)

        if config.perClipSeconds != nil {
            progress("対象動画: \(config.videos.count) 本（自動モード: 1本ごとに2〜3秒をランダム選択）")
        } else {
            progress("対象動画: \(config.videos.count) 本, 1本あたり約 \(String(format: "%.1f", durations.first ?? 0)) 秒")
        }

        // フェーズ: クリップ抽出 0〜70%, 結合 70〜78%, フェードイン/タイトル 78〜85%,
        // BGM合成 85〜92%, 終端フェード 92〜96%, 黒みへの結合 96〜100%
        let total = config.videos.count
        var clipFiles: [URL] = []
        for (idx, vpath) in config.videos.enumerated() {
            try checkCancel()
            setProgress(Double(idx) / Double(total) * 0.7)
            setDetail("クリップ抽出中… \(idx + 1)/\(total): \(vpath.lastPathComponent)")
            progress("[\(idx + 1)/\(total)] \(vpath.lastPathComponent)")

            let requestedClipSec = durations[idx]
            let dur = getDuration(ffprobe: ffprobe, path: vpath.path) ?? 0
            let offset = Double(config.offsetSec)
            let latest = dur > requestedClipSec + offset ? dur - requestedClipSec : 0
            let earliest = min(offset, latest)

            // ソース動画が短く、要求した秒数(自動モードでは2〜3秒がランダムに割り当てられるため
            // 特に起きやすい)を素材が満たせない場合、ffmpegの`-t`は単に素材が尽きた時点で
            // 止まる(足りない分は生成されない)。この実際の抽出長を`durations[idx]`に
            // 反映せず「要求した秒数」のまま後段のディゾルブ結合(xfadeのoffset計算)に渡すと、
            // 実際には存在しないはずの区間を要求してしまい、そこだけ最後のフレームが
            // 静止して見える(freeze)不具合になっていた。ここで実際に抽出できる長さに
            // 丸め、以降の結合・尺見積もりは実測ベースで一貫させる。
            let effectiveClipSec = dur > 0 ? min(requestedClipSec, max(0.1, dur - earliest)) : requestedClipSec
            durations[idx] = effectiveClipSec

            // 最大5回リトライして暗い/止まったシーンを避ける。単純な乱数だと5回とも
            // 同じ(静止した)区間に偏って当たることがあり、動画全体が静止シーンに見えて
            // しまう原因になっていたため、範囲を5等分したバケツごとに1回ずつ試す
            // (バケツ内では乱数でずらし、再生成のたびに多少違う位置を試せるようにする)。
            var goodStart: Double = earliest
            let attempts = 5
            let span = latest - earliest
            for attempt in 0..<attempts {
                let candidate: Double
                if span > 0 {
                    let bucketWidth = span / Double(attempts)
                    let bucketStart = earliest + bucketWidth * Double(attempt)
                    let bucketEnd = attempt == attempts - 1 ? latest : bucketStart + bucketWidth
                    candidate = bucketEnd > bucketStart ? Double.random(in: bucketStart...bucketEnd) : bucketStart
                } else {
                    candidate = earliest
                }
                if isGoodClip(ffmpeg: ffmpeg, path: vpath.path, start: candidate, duration: effectiveClipSec) {
                    goodStart = candidate
                    break
                }
                if attempt == attempts - 1 { goodStart = candidate } // 全滅なら最終走査地点をあきらめて使う
            }

            let outClip = tmpDir.appendingPathComponent(String(format: "clip_%04d.mp4", idx))
            // fps・解像度を統一(縦動画はピラーボックスで1920x1080に収める)
            // setsar=1で正方形ピクセルに矯正する — ソース側のSAR(非正方形ピクセル)を
            // 引き継いだまま1920x1080の固定解像度にscale/padすると、再生側がそのSARを
            // 使って再度引き伸ばして表示してしまい、動画によって画像が伸びて見える原因になる。
            let normalizeFilter = "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p"
            if hasAudioStream(ffprobe: ffprobe, path: vpath.path) {
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
            } else {
                // 音声トラックを持たない動画(無音のスクリーン録画等)。無音のダミー音声を
                // 合成して必ず音声トラックを付ける — 後段のディゾルブ結合は全クリップの
                // 音声トラック([i:a])を前提にfilter_complexを組むため、1本でも音声が
                // 無いとその段でffmpegが「matches no streams」エラーで失敗する。
                try await runFFmpeg(ffmpeg, [
                    "-y", "-ss", String(goodStart), "-i", vpath.path,
                    "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", String(effectiveClipSec),
                    "-vf", normalizeFilter,
                    "-map", "0:v", "-map", "1:a",
                    "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
                    "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-ar", "44100",
                    "-movflags", "+faststart",
                    outClip.path,
                ], onCancel: onCancel)
            }
            clipFiles.append(outClip)
        }

        try checkCancel()

        // クリップを結合(ディゾルブトランジション付き)。自動モードではクリップごとに秒数が
        // 異なるため、トランジションの重なり幅・xfadeのoffsetは隣接ペアごとに個別計算する
        // (お互いの短い方の半分を上限にする点はmainDuration(durations:transitionSec:)と共通)。
        let concatOut = tmpDir.appendingPathComponent("concat.mp4")
        let clipCount = clipFiles.count

        if clipCount == 1 {
            try FileManager.default.copyItem(at: clipFiles[0], to: concatOut)
        } else if config.transitionSec <= 0 {
            let concatDurTotal = durations.reduce(0, +)
            let listFile = tmpDir.appendingPathComponent("clips.txt")
            let listContent = clipFiles.map { "file '\($0.path)'" }.joined(separator: "\n")
            try listContent.write(to: listFile, atomically: true, encoding: .utf8)
            setDetail("クリップを結合中…")
            try await runFFmpegWithProgress(ffmpeg, [
                "-y", "-f", "concat", "-safe", "0",
                "-i", listFile.path, "-c", "copy", concatOut.path,
            ], totalSec: concatDurTotal, baseProgress: 0.70, rangeProgress: 0.08, setProgress: setProgress, onCancel: onCancel)
        } else {
            var args: [String] = ["-y"]
            for clip in clipFiles {
                args += ["-i", clip.path]
            }
            var vf = ""
            var af = ""
            var runningLength = durations[0]
            for i in 0..<(clipCount - 1) {
                let transDur = min(config.transitionSec, min(durations[i], durations[i + 1]) / 2)
                let offset = runningLength - transDur
                let vIn = i == 0 ? "[0:v]" : "[v\(i)]"
                let aIn = i == 0 ? "[0:a]" : "[a\(i)]"
                let vOut = i == clipCount - 2 ? "[vout]" : "[v\(i + 1)]"
                let aOut = i == clipCount - 2 ? "[aout]" : "[a\(i + 1)]"
                vf += "\(vIn)[\(i + 1):v]xfade=transition=fade:duration=\(String(format: "%.3f", transDur)):offset=\(String(format: "%.3f", offset))\(vOut);"
                af += "\(aIn)[\(i + 1):a]acrossfade=d=\(String(format: "%.3f", transDur)):c1=tri:c2=tri\(aOut);"
                runningLength = offset + durations[i + 1]
            }
            let filterComplex = String((vf + af).dropLast())
            args += ["-filter_complex", filterComplex]
            args += ["-map", "[vout]", "-map", "[aout]"]
            args += ["-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset)]
            args += ["-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2"]
            args += [concatOut.path]
            let concatDurTotal = runningLength
            setDetail("ディゾルブで結合中…")
            try await runFFmpegWithProgress(ffmpeg, args, totalSec: concatDurTotal, baseProgress: 0.70, rangeProgress: 0.08, setProgress: setProgress, onCancel: onCancel)
        }

        try checkCancel()

        // ── フェードイン+タイトルオーバーレイを全体に適用(終端の演出は末尾でまとめて行うため、ここではフェードインのみ) ──
        let estimatedDur = mainDuration(durations: durations, transitionSec: config.transitionSec)
        let totalDur = getDuration(ffprobe: ffprobe, path: concatOut.path) ?? estimatedDur
        let fadeInSec = min(1.0, totalDur / 6)
        let fadedIn = tmpDir.appendingPathComponent("faded.mp4")
        setProgress(0.80)
        setDetail("フェードイン・タイトルを適用中…")

        let title = config.titleText

        if !title.isEmpty {
            let overlayPng = tmpDir.appendingPathComponent("overlay.png")
            renderTitleOverlay(text: title, fontSize: 36, width: 1920, height: 1080, position: .topLeft, to: overlayPng)
            try await runFFmpeg(ffmpeg, [
                "-y", "-i", concatOut.path, "-i", overlayPng.path,
                "-filter_complex", "[0:v][1:v]overlay=0:0,fade=t=in:st=0:d=\(String(format: "%.3f", fadeInSec))",
                "-af", "afade=t=in:st=0:d=\(String(format: "%.3f", fadeInSec))",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                fadedIn.path,
            ], onCancel: onCancel)
        } else {
            try await runFFmpeg(ffmpeg, [
                "-y", "-i", concatOut.path,
                "-vf", "fade=t=in:st=0:d=\(String(format: "%.3f", fadeInSec))",
                "-af", "afade=t=in:st=0:d=\(String(format: "%.3f", fadeInSec))",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                fadedIn.path,
            ], onCancel: onCancel)
        }

        try checkCancel()

        // ── タイトルカード(黒画面+中央タイトル)を先頭に追加 ──
        let withTitle: URL
        if !title.isEmpty {
            let cardDur = titleCardDurationSec
            let cardFade = 0.5
            let titleCard = tmpDir.appendingPathComponent("titlecard.mp4")
            let titleCardPng = tmpDir.appendingPathComponent("titlecard.png")
            setProgress(0.83)
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
            try "file '\(titleCard.path)'\nfile '\(fadedIn.path)'".write(to: cardListFile, atomically: true, encoding: .utf8)
            let titledOut = tmpDir.appendingPathComponent("titled.mp4")
            try await runFFmpeg(ffmpeg, [
                "-y", "-f", "concat", "-safe", "0",
                "-i", cardListFile.path, "-c", "copy", titledOut.path,
            ], onCancel: onCancel)
            withTitle = titledOut
        } else {
            withTitle = fadedIn
        }

        try checkCancel()

        // ── BGM合成(フェードインのみ。フェードアウトは末尾で元音声と合わせて一括で行う) ──
        let preOutroDur = getDuration(ffprobe: ffprobe, path: withTitle.path) ?? totalDur
        let bgmMixed: URL
        if !config.musicPath.isEmpty, FileManager.default.fileExists(atPath: config.musicPath) {
            // BGMをループ→preOutroDurに切り詰め→フェードイン適用→一時ファイルへ
            let bgmFadeInDur = min(2.0, preOutroDur / 4)
            let bgmReady = tmpDir.appendingPathComponent("bgm_ready.aac")
            setDetail("BGMを準備中…")
            try await runFFmpeg(ffmpeg, [
                "-y",
                "-stream_loop", "-1", "-i", config.musicPath,
                "-t", String(format: "%.3f", preOutroDur),
                "-af", "volume=\(config.bgmVolume),afade=t=in:st=0:d=\(bgmFadeInDur)",
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                bgmReady.path,
            ], onCancel: onCancel)
            setProgress(0.85)
            setDetail("BGMを合成中…")
            let mixedOut = tmpDir.appendingPathComponent("bgm_mixed.mp4")
            try await runFFmpegWithProgress(ffmpeg, [
                "-y",
                "-i", withTitle.path,
                "-i", bgmReady.path,
                "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=first[aout]",
                "-map", "0:v", "-map", "[aout]",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                "-t", String(format: "%.3f", preOutroDur),
                mixedOut.path,
            ], totalSec: preOutroDur, baseProgress: 0.85, rangeProgress: 0.07, setProgress: setProgress, onCancel: onCancel)
            bgmMixed = mixedOut
        } else {
            bgmMixed = withTitle
        }

        try checkCancel()

        // ── 終端の演出: 音声(元音声+BGM合成後)をフェードアウト → 続けて映像もフェードアウトして黒みに → 黒みを2秒保持 ──
        setProgress(0.92)
        setDetail("終端のフェードを適用中…")
        let coreDur = preOutroDur
        // 音声フェード→映像フェードの順に、互いに重ならないよう終端の尺から逆算する。
        var videoFadeSec = min(1.0, coreDur / 8)
        var audioFadeSec = min(1.0, coreDur / 8)
        if videoFadeSec + audioFadeSec > coreDur / 2 {
            videoFadeSec = coreDur / 4
            audioFadeSec = coreDur / 4
        }
        let videoFadeStart = max(0, coreDur - videoFadeSec)
        let audioFadeStart = max(0, videoFadeStart - audioFadeSec)
        let outroFaded = tmpDir.appendingPathComponent("outro_faded.mp4")
        try await runFFmpeg(ffmpeg, [
            "-y", "-i", bgmMixed.path,
            "-vf", "fade=t=out:st=\(String(format: "%.3f", videoFadeStart)):d=\(String(format: "%.3f", videoFadeSec))",
            "-af", "afade=t=out:st=\(String(format: "%.3f", audioFadeStart)):d=\(String(format: "%.3f", audioFadeSec))",
            "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
            "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
            outroFaded.path,
        ], onCancel: onCancel)

        try checkCancel()

        setProgress(0.96)
        setDetail("黒みを追加中…")
        let blackHold = tmpDir.appendingPathComponent("black_hold.mp4")
        try await runFFmpeg(ffmpeg, [
            "-y",
            "-f", "lavfi", "-i", "color=c=black:s=1920x1080:r=30:d=\(blackHoldSec)",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
            "-t", String(blackHoldSec),
            "-c:v", "libx264", "-preset", "fast", "-crf", String(config.qualityPreset),
            "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
            blackHold.path,
        ], onCancel: onCancel)

        let finalListFile = tmpDir.appendingPathComponent("final_list.txt")
        try "file '\(outroFaded.path)'\nfile '\(blackHold.path)'".write(to: finalListFile, atomically: true, encoding: .utf8)
        try await runFFmpeg(ffmpeg, [
            "-y", "-f", "concat", "-safe", "0",
            "-i", finalListFile.path, "-c", "copy", config.outputPath,
        ], onCancel: onCancel)

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

    /// 音声トラックを持たない動画(無音のスクリーン録画等)を検出する。判定できない場合は
    /// 「ある」扱いにする(安全側 — 誤って無音判定すると不要なanullsrc合成が走るだけで実害は
    /// ないが、誤って「音声あり」判定した無音動画を後段のディゾルブ結合に渡すと
    /// filter_complexが「matches no streams」で失敗するため)。
    private static func hasAudioStream(ffprobe: String, path: String) -> Bool {
        guard let output = try? SyncExec.run(ffprobe, [
            "-v", "quiet", "-print_format", "json",
            "-show_streams", "-select_streams", "a",
            path,
        ]) else { return true }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else { return true }
        return !streams.isEmpty
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
