import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DurationMode { case clip, total }

@MainActor
class VideoMakerViewModel: ObservableObject {
    @Published var folderPath = "/Volumes/backup1/leo_video/2024/03"
    @Published var musicPath = UserDefaults.standard.string(forKey: "defaultMusicPath") ?? ""
    @Published var outputPath = ""
    @Published var videos: [URL] = []
    @Published var selectedVideos = Set<URL>()
    @Published var durationMode: DurationMode = .total
    @Published var qualityPreset: Int = 18  // CRF: 低いほど高画質
    @Published var clipSec: Int = 8
    @Published var totalSec: Int = 30
    @Published var offsetSec: Int = 3
    @Published var bgmVolume: Double = 0.3
    @Published var origVolume: Double = 0.7
    @Published var transitionSec: Double = 0.5
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var showDone = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showOverwriteConfirm = false
    @Published var titleText = ""
    @Published var maxFileCount: Int = 0
    @Published var useMaxFileCount = false
    @Published var randomMode = false

    private let videoExts: Set<String> = ["mp4","mov","avi","m4v","mkv","mts","m2ts","3gp"]

    func loadDefaults() {
        outputPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/まとめ動画.mp4").path

        let defaultFolder = "/Volumes/backup1/leo_video/2024/03"
        let url = URL(fileURLWithPath: defaultFolder)
        guard FileManager.default.fileExists(atPath: defaultFolder) else { return }
        folderPath = defaultFolder
        titleText = detectTitle(from: defaultFolder)
        videos = findVideos(in: url)
    }

    var totalDisplay: String {
        let t = clipSec * videos.count
        return "\(t / 60)分\(String(format: "%02d", t % 60))秒"
    }

    var clipDisplay: String {
        guard !videos.isEmpty else { return "-" }
        let c = Double(totalSec) / Double(videos.count)
        return String(format: "%.1f秒", c)
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        titleText = detectTitle(from: url.path)
        videos = findVideos(in: url)
    }

    func pickMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        musicPath = url.path
        UserDefaults.standard.set(musicPath, forKey: "defaultMusicPath")
    }

    func clearMusic() {
        musicPath = ""
        UserDefaults.standard.removeObject(forKey: "defaultMusicPath")
    }

    func pickOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4")!]
        panel.nameFieldStringValue = "まとめ動画.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputPath = url.path
    }

    func removeSelected() {
        videos.removeAll { selectedVideos.contains($0) }
        selectedVideos.removeAll()
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
    }

    func playOutput() {
        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
    }

    func generate() {
        // 出力ファイルが既に存在する場合は確認ダイアログを出す
        if FileManager.default.fileExists(atPath: outputPath) {
            showOverwriteConfirm = true
            return
        }
        startGenerate()
    }

    func startGenerate() {
        isRunning = true
        progress = 0
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try await self.doGenerate()
                await MainActor.run { self.showDone = true }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
            await MainActor.run {
                self.isRunning = false
                self.statusMessage = "完成！"
            }
        }
    }

    // MARK: - 生成処理

    private func doGenerate() async throws {
        let tmpDir = URL(fileURLWithPath: outputPath)
            .deletingLastPathComponent()
            .appendingPathComponent(".video_tmp_\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let effectiveClipSec: Double
        if durationMode == .total {
            effectiveClipSec = Double(totalSec) / Double(videos.count)
        } else {
            effectiveClipSec = Double(clipSec)
        }

        // フェーズ: クリップ抽出 0〜80%, 結合 80〜90%, BGM 90〜100%
        let total = videos.count
        var clipFiles: [URL] = []
        for (idx, vpath) in videos.enumerated() {
            await setProgress(Double(idx) / Double(total) * 0.8,
                              "クリップ抽出中… \(idx + 1)/\(total): \(vpath.lastPathComponent)")

            let dur = getDuration(path: vpath.path) ?? 0
            let offset = Double(offsetSec)
            let latest = dur > effectiveClipSec + offset ? dur - effectiveClipSec : 0
            let earliest = min(offset, latest)

            // 最大5回リトライして暗い/止まったシーンを避ける
            var goodStart: Double = earliest
            for attempt in 0..<5 {
                let candidate = latest > earliest
                    ? Double.random(in: earliest...latest)
                    : earliest
                if isGoodClip(path: vpath.path, start: candidate, duration: effectiveClipSec) {
                    goodStart = candidate
                    break
                }
                if attempt == 4 { goodStart = candidate } // 最終はあきらめて使う
            }

            let outClip = tmpDir.appendingPathComponent(String(format: "clip_%04d.mp4", idx))
            // fps・解像度を統一（縦動画はピラーボックスで1920x1080に収める）
            let normalizeFilter = "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p"
            try run("ffmpeg", args: [
                "-y", "-ss", String(goodStart), "-i", vpath.path,
                "-t", String(effectiveClipSec),
                "-vf", normalizeFilter,
                "-af", "volume=\(origVolume),aresample=44100,aformat=channel_layouts=stereo",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-ar", "44100",
                "-movflags", "+faststart",
                outClip.path
            ])
            clipFiles.append(outClip)
        }

        // クリップを結合（ディゾルブトランジション付き）
        let concatOut = tmpDir.appendingPathComponent("concat.mp4")
        let clipCount = clipFiles.count
        let transDur = min(transitionSec, effectiveClipSec / 2)

        if clipCount == 1 {
            try FileManager.default.copyItem(at: clipFiles[0], to: concatOut)
        } else if transDur <= 0 {
            let concatDurTotal = Double(clipCount) * effectiveClipSec
            let listFile = tmpDir.appendingPathComponent("clips.txt")
            let listContent = clipFiles.map { "file '\($0.path)'" }.joined(separator: "\n")
            try listContent.write(to: listFile, atomically: true, encoding: .utf8)
            try await runWithProgress("ffmpeg", args: [
                "-y", "-f", "concat", "-safe", "0",
                "-i", listFile.path, "-c", "copy", concatOut.path
            ], totalSec: concatDurTotal, baseProgress: 0.8, rangeProgress: 0.05, label: "クリップを結合中…")
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
            args += ["-c:v", "libx264", "-preset", "fast", "-crf", String(qualityPreset)]
            args += ["-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2"]
            args += [concatOut.path]
            let concatDurTotal = Double(clipCount) * effectiveClipSec - Double(clipCount - 1) * transDur
            try await runWithProgress("ffmpeg", args: args, totalSec: concatDurTotal, baseProgress: 0.8, rangeProgress: 0.05, label: "ディゾルブで結合中…")
        }

        // ── フェード＋タイトルオーバーレイを全体に適用 ──────
        let estimatedDur = Double(clipCount) * effectiveClipSec - Double(max(0, clipCount - 1)) * min(transitionSec, effectiveClipSec / 2)
        let totalDur = getDuration(path: concatOut.path) ?? estimatedDur
        let fadeSec = min(1.0, totalDur / 6)
        let fadeOutSt = max(0, totalDur - fadeSec)
        let fadedOut = tmpDir.appendingPathComponent("faded.mp4")
        await setProgress(0.85, "フェード・タイトルを適用中…")

        let title = titleText

        if !title.isEmpty {
            let overlayPng = tmpDir.appendingPathComponent("overlay.png")
            renderTitleOverlay(text: title, fontSize: 36, width: 1920, height: 1080, position: .topLeft, to: overlayPng)
            try run("ffmpeg", args: [
                "-y", "-i", concatOut.path, "-i", overlayPng.path,
                "-filter_complex", "[0:v][1:v]overlay=0:0,fade=t=in:st=0:d=\(String(format:"%.3f",fadeSec)),fade=t=out:st=\(String(format:"%.3f",fadeOutSt)):d=\(String(format:"%.3f",fadeSec))",
                "-af", "afade=t=in:st=0:d=\(String(format:"%.3f",fadeSec)),afade=t=out:st=\(String(format:"%.3f",fadeOutSt)):d=\(String(format:"%.3f",fadeSec))",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                fadedOut.path
            ])
        } else {
            try run("ffmpeg", args: [
                "-y", "-i", concatOut.path,
                "-vf", "fade=t=in:st=0:d=\(String(format:"%.3f",fadeSec)),fade=t=out:st=\(String(format:"%.3f",fadeOutSt)):d=\(String(format:"%.3f",fadeSec))",
                "-af", "afade=t=in:st=0:d=\(String(format:"%.3f",fadeSec)),afade=t=out:st=\(String(format:"%.3f",fadeOutSt)):d=\(String(format:"%.3f",fadeSec))",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(qualityPreset),
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                fadedOut.path
            ])
        }

        // ── タイトルカード（黒画面+中央タイトル）を先頭に追加 ─
        let withTitle: URL
        if !title.isEmpty {
            let cardDur = 3.0
            let cardFade = 0.5
            let titleCard = tmpDir.appendingPathComponent("titlecard.mp4")
            let titleCardPng = tmpDir.appendingPathComponent("titlecard.png")
            await setProgress(0.87, "タイトルカードを作成中…")
            renderTitleOverlay(text: title, fontSize: 80, width: 1920, height: 1080, position: .center, to: titleCardPng)
            try run("ffmpeg", args: [
                "-y",
                "-loop", "1", "-i", titleCardPng.path,
                "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                "-t", String(cardDur),
                "-vf", "fps=30,fade=t=in:st=0:d=\(cardFade),fade=t=out:st=\(cardDur-cardFade):d=\(cardFade)",
                "-af", "afade=t=in:st=0:d=\(cardFade),afade=t=out:st=\(cardDur-cardFade):d=\(cardFade)",
                "-c:v", "libx264", "-preset", "fast", "-crf", String(qualityPreset),
                "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                titleCard.path
            ])
            let cardListFile = tmpDir.appendingPathComponent("card_list.txt")
            try "file '\(titleCard.path)'\nfile '\(fadedOut.path)'".write(to: cardListFile, atomically: true, encoding: .utf8)
            let titledOut = tmpDir.appendingPathComponent("titled.mp4")
            try run("ffmpeg", args: [
                "-y", "-f", "concat", "-safe", "0",
                "-i", cardListFile.path, "-c", "copy", titledOut.path
            ])
            withTitle = titledOut
        } else {
            withTitle = fadedOut
        }

        // ── BGM合成 ────────────────────────────────────────
        let finalDur = getDuration(path: withTitle.path) ?? totalDur
        if !musicPath.isEmpty, FileManager.default.fileExists(atPath: musicPath) {
            // BGMをループ→finalDurに切り詰め→フェード適用→一時ファイルへ
            let bgmFadeDur = min(2.0, finalDur / 4)
            let bgmFadeOutSt = max(0, finalDur - bgmFadeDur)
            let bgmReady = tmpDir.appendingPathComponent("bgm_ready.aac")
            try run("ffmpeg", args: [
                "-y",
                "-stream_loop", "-1", "-i", musicPath,
                "-t", String(format: "%.3f", finalDur),
                "-af", "volume=\(bgmVolume),afade=t=in:st=0:d=\(bgmFadeDur),afade=t=out:st=\(String(format:"%.3f",bgmFadeOutSt)):d=\(bgmFadeDur)",
                "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
                bgmReady.path
            ])
            await setProgress(0.93, "BGMを合成中…")
            try await runWithProgress("ffmpeg", args: [
                "-y",
                "-i", withTitle.path,
                "-i", bgmReady.path,
                "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=first[aout]",
                "-map", "0:v", "-map", "[aout]",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                "-t", String(format: "%.3f", finalDur),
                outputPath
            ], totalSec: finalDur, baseProgress: 0.93, rangeProgress: 0.07, label: "BGMを合成中…")
        } else {
            try FileManager.default.copyItem(atPath: withTitle.path, toPath: outputPath)
        }
    }

    // MARK: - タイトル画像生成（drawtext の代替）

    enum TitlePosition { case topLeft, center }

    private func renderTitleOverlay(text: String, fontSize: CGFloat, width: Int, height: Int, position: TitlePosition, to url: URL) {
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

    // MARK: - タイトル検出

    private func detectTitle(from path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        let last = parts.last ?? ""
        let secondLast = parts.dropLast().last ?? ""
        let months = ["01":"January","02":"February","03":"March","04":"April",
                      "05":"May","06":"June","07":"July","08":"August",
                      "09":"September","10":"October","11":"November","12":"December"]
        if let monthName = months[last], secondLast.count == 4, Int(secondLast) != nil {
            return "\(monthName), \(secondLast)"
        }
        if last.count == 4, Int(last) != nil { return last }
        return ""
    }

    // MARK: - クリップ品質チェック

    /// true = 使えるクリップ（暗すぎず、止まっていない）
    private func isGoodClip(path: String, start: Double, duration: Double) -> Bool {
        let result = try? runOutput("ffmpeg", args: [
            "-ss", String(start),
            "-i", path,
            "-t", String(min(duration, 3.0)), // 最初の3秒だけチェック
            "-vf", "blackdetect=d=0.5:pix_th=0.10,freezedetect=n=-60dB:d=0.5",
            "-an", "-f", "null", "-"
        ])
        guard let output = result else { return true }
        // black_start や freeze_start が出てきたらNG
        let isBad = output.contains("black_start") || output.contains("freeze_start")
        return !isBad
    }

    // MARK: - ヘルパー

    func applyFileLimits() {
        var list = videos
        if randomMode {
            list.shuffle()
        }
        if useMaxFileCount, maxFileCount > 0, list.count > maxFileCount {
            list = Array(list.prefix(maxFileCount))
        }
        videos = list
    }

    private func findVideos(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil) else { return [] }
        var result = enumerator
            .compactMap { $0 as? URL }
            .filter { videoExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
        if randomMode {
            result.shuffle()
        }
        if useMaxFileCount, maxFileCount > 0, result.count > maxFileCount {
            result = Array(result.prefix(maxFileCount))
        }
        return result
    }

    private func getDuration(path: String) -> Double? {
        let result = try? runOutput("ffprobe", args: [
            "-v", "quiet", "-print_format", "json", "-show_format", path
        ])
        guard let data = result?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fmt = json["format"] as? [String: Any],
              let durStr = fmt["duration"] as? String else { return nil }
        return Double(durStr)
    }

    // ffmpegの-progressをファイルに書かせてポーリングで進捗取得
    private func runWithProgress(_ bin: String, args: [String],
                                  totalSec: Double, baseProgress: Double,
                                  rangeProgress: Double, label: String) async throws {
        let binPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/\(bin)")
            ? "/opt/homebrew/bin/\(bin)" : "/usr/local/bin/\(bin)"
        let progressFile = URL(fileURLWithPath: "/tmp/kvm_ffmpeg_progress_\(Int(Date().timeIntervalSince1970)).txt")
        final class State: @unchecked Sendable { var isRunning = true; var exitCode: Int32 = 0 }
        let state = State()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binPath)
        task.arguments = args + ["-progress", progressFile.path, "-nostats"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice  // バッファ詰まり防止
        task.terminationHandler = { t in
            state.exitCode = t.terminationStatus
            state.isRunning = false
        }
        try task.run()

        // 100msごとにファイルをポーリング
        while state.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let content = try? String(contentsOf: progressFile, encoding: .utf8) {
                for line in content.components(separatedBy: "\n").reversed() {
                    if line.hasPrefix("out_time_ms="), let ms = Double(line.dropFirst("out_time_ms=".count)), ms > 0 {
                        let frac = totalSec > 0 ? min(ms / 1_000_000 / totalSec, 1.0) : 0
                        await setProgress(baseProgress + frac * rangeProgress, label)
                        break
                    }
                }
            }
        }
        try? FileManager.default.removeItem(at: progressFile)
        if state.exitCode != 0 {
            throw NSError(domain: "ffmpeg", code: Int(state.exitCode),
                          userInfo: [NSLocalizedDescriptionKey: "ffmpeg failed (code \(state.exitCode))"])
        }
        await setProgress(baseProgress + rangeProgress, label)
    }

    @discardableResult
    private func run(_ bin: String, args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/\(bin)")
        if !FileManager.default.fileExists(atPath: task.executableURL!.path) {
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/\(bin)")
        }
        task.arguments = args
        // 成功時は出力不要なので /dev/null へ。エラー時だけ読む
        let errPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errPipe
        try task.run()
        // errPipe を非同期で読み続けてバッファ詰まりを防ぐ
        final class DataBox: @unchecked Sendable { var data = Data() }
        let box = DataBox()
        let sem = DispatchSemaphore(value: 0)
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if d.isEmpty {
                errPipe.fileHandleForReading.readabilityHandler = nil
                sem.signal()
            } else {
                box.data.append(d)
            }
        }
        task.waitUntilExit()
        sem.wait()
        if task.terminationStatus != 0 {
            let msg = String(data: box.data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "ffmpeg", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return ""
    }

    private func runOutput(_ bin: String, args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/\(bin)")
        if !FileManager.default.fileExists(atPath: task.executableURL!.path) {
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/\(bin)")
        }
        task.arguments = args
        // stdout と stderr を同じパイプにまとめてデッドロック回避
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func setProgress(_ value: Double, _ msg: String) async {
        await MainActor.run {
            progress = value
            statusMessage = msg
        }
    }
}
