import Foundation
import SwiftUI

enum DownloadKind: String, CaseIterable, Identifiable {
    case audio
    case video
    var id: String { rawValue }
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published var isRunning = false
    @Published var progress: Double = 0          // 0...1（不明なときは負）
    @Published var statusLine = ""               // 進捗の1行サマリ
    @Published var log = ""                      // yt-dlp の生ログ

    // ツールの場所（起動時に解決）
    let ytdlpPath = ToolLocator.locate("yt-dlp")
    let ffmpegPath = ToolLocator.locate("ffmpeg")

    var toolsReady: Bool { ytdlpPath != nil && ffmpegPath != nil }

    private var process: Process?

    /// 選択された種別を順番にダウンロードする。
    /// - Parameter videoHeight: Video の最大解像度（px）。nil は最高画質。
    func start(url: String, kinds: [DownloadKind], videoHeight: Int?, outputDir: URL) {
        guard !isRunning, let ytdlp = ytdlpPath else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appendLog("⚠️ URL が空です。\n")
            return
        }
        isRunning = true
        progress = -1
        log = ""
        statusLine = "準備中…"

        Task.detached { [weak self] in
            guard let self else { return }
            for kind in kinds {
                let ok = await self.runOne(ytdlp: ytdlp, url: trimmed, kind: kind,
                                           videoHeight: videoHeight, outputDir: outputDir)
                if !ok { break }
            }
            await MainActor.run {
                self.isRunning = false
                self.process = nil
                self.progress = self.statusLine.contains("失敗") ? -1 : 1
                if !self.statusLine.contains("失敗") {
                    self.statusLine = "完了しました ✅"
                }
            }
        }
    }

    func cancel() {
        process?.terminate()
    }

    // MARK: - 1ジョブ実行

    private func runOne(ytdlp: String, url: String, kind: DownloadKind,
                        videoHeight: Int?, outputDir: URL) async -> Bool {
        let videoLabel = videoHeight.map { "\($0)p" } ?? "最高画質"
        await MainActor.run {
            self.statusLine = kind == .audio ? "音声をダウンロード中…" : "動画をダウンロード中…"
            self.appendLog("\n=== \(kind == .audio ? "AUDIO (mp3 / 最高音質)" : "VIDEO (\(videoLabel) / mp4)") ===\n")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = buildArguments(url: url, kind: kind, videoHeight: videoHeight, outputDir: outputDir)

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe

        await MainActor.run { self.process = proc }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.handleOutput(text) }
        }

        do {
            try proc.run()
        } catch {
            await MainActor.run {
                self.appendLog("❌ 起動に失敗: \(error.localizedDescription)\n")
                self.statusLine = "失敗"
            }
            return false
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            proc.terminationHandler = { _ in cont.resume() }
        }
        outPipe.fileHandleForReading.readabilityHandler = nil

        let success = proc.terminationStatus == 0
        if !success {
            await MainActor.run { self.statusLine = "失敗（終了コード \(proc.terminationStatus)）" }
        }
        return success
    }

    /// yt-dlp の引数を組み立てる。
    private func buildArguments(url: String, kind: DownloadKind, videoHeight: Int?, outputDir: URL) -> [String] {
        var args: [String] = [
            "--newline",                 // 進捗を行単位で flush
            "--no-playlist",             // 単一動画のみ
            "--restrict-filenames",      // 安全なファイル名
            "-o", outputDir.appendingPathComponent("%(title)s [%(id)s].%(ext)s").path,
        ]
        if let ffmpeg = ffmpegPath {
            args += ["--ffmpeg-location", ffmpeg]
        }

        switch kind {
        case .audio:
            // 最高音質の音声を mp3 に変換して取得。
            args += [
                "-f", "bestaudio/best",
                "--extract-audio",
                "--audio-format", "mp3",
                "--audio-quality", "0",   // 0 = 最高音質（VBR）
            ]
        case .video:
            // 指定解像度（最大）の映像 + 最高音質を mp4 に結合。
            let fmt: String
            if let h = videoHeight {
                fmt = "bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]/bestvideo+bestaudio/best"
            } else {
                fmt = "bestvideo+bestaudio/best"
            }
            args += [
                "-f", fmt,
                "--merge-output-format", "mp4",
            ]
        }
        args.append(url)
        return args
    }

    // MARK: - 出力処理

    private func handleOutput(_ text: String) {
        appendLog(text)
        // 進捗パーセントを拾う: 例 "[download]  42.1% of 10.00MiB at ..."
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            if let pct = Self.parsePercent(String(line)) {
                progress = pct / 100
                statusLine = String(line).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    private func appendLog(_ text: String) {
        log += text
        if log.count > 40_000 {
            log = String(log.suffix(30_000))
        }
    }

    private static func parsePercent(_ line: String) -> Double? {
        guard line.contains("[download]"), let range = line.range(of: "%") else { return nil }
        let before = line[..<range.lowerBound]
        let token = before.reversed().prefix { $0.isNumber || $0 == "." }
        let number = String(token.reversed())
        return Double(number)
    }
}
