import Foundation
import SwiftUI

enum DownloadKind: String, CaseIterable, Identifiable {
    case audio
    case video
    var id: String { rawValue }
}

@MainActor
final class YtDlpManager: ObservableObject {
    @Published var isRunning = false
    @Published var progress: Double = 0          // 0...1(不明なときは負)
    @Published var statusLine = ""               // 進捗の1行サマリ
    @Published var log = ""                      // yt-dlp の生ログ

    // ツールの場所(起動時に解決)
    let ytdlpPath = ToolLocator.locate("yt-dlp")
    let ffmpegPath = ToolLocator.locate("ffmpeg")

    var toolsReady: Bool { ytdlpPath != nil && ffmpegPath != nil }

    private var process: Process?
    /// プレイリストダウンロード中の "(3/23) " のような接頭辞。単発動画では空文字のまま。
    private var playlistItemLabel = ""

    /// 選択された種別を順番にダウンロードする。
    /// - Parameter videoHeight: Video の最大解像度(px)。nil は最高画質。
    /// - Parameter isPlaylist: true ならプレイリスト全体を `保存先/ダウンロード名/` にまとめて落とす。
    /// - Parameter customName: 空でなければ、自動取得したタイトルの代わりにこの名前を使う
    ///   (プレイリストならフォルダ名、単発動画ならファイル名に反映される)。
    func start(url: String, kinds: [DownloadKind], videoHeight: Int?, outputDir: URL, isPlaylist: Bool = false, customName: String = "") {
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
                                           videoHeight: videoHeight, outputDir: outputDir, isPlaylist: isPlaylist,
                                           customName: customName)
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

    /// リンクを貼り付けた直後に呼ぶ軽量メタデータ取得(ダウンロードはしない)。
    /// プレイリストならプレイリストのタイトル、単発動画なら動画のタイトルを1個だけ取得して返す。
    /// 取得失敗(無効なURL・削除済み動画・ネットワークエラー等)は nil を返すだけで、
    /// 呼び出し側(名前欄)はユーザーが手入力すれば問題なく続行できる。
    func fetchTitle(url: String, isPlaylist: Bool) async -> String? {
        guard let ytdlp = ytdlpPath else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ytdlp)
            // プレイリストは`--playlist-end 1`で1件目の列挙だけに留め、全項目を舐めずに
            // プレイリスト自体のタイトルだけを高速に取得する(実測1秒前後)。
            proc.arguments = isPlaylist
                ? ["--flat-playlist", "--no-warnings", "--playlist-end", "1", "--print", "%(playlist_title)s", trimmed]
                : ["--no-warnings", "--skip-download", "--print", "%(title)s", trimmed]

            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            do {
                try proc.run()
            } catch {
                return nil
            }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, text != "NA" else { return nil }
            return text
        }.value
    }

    // MARK: - 1ジョブ実行

    private func runOne(ytdlp: String, url: String, kind: DownloadKind,
                        videoHeight: Int?, outputDir: URL, isPlaylist: Bool, customName: String) async -> Bool {
        let videoLabel = videoHeight.map { "\($0)p" } ?? "最高画質"
        playlistItemLabel = ""
        await MainActor.run {
            self.statusLine = kind == .audio ? "音声をダウンロード中…" : "動画をダウンロード中…"
            self.appendLog("\n=== \(kind == .audio ? "AUDIO (mp3 / 最高音質)" : "VIDEO (\(videoLabel) / mp4)") ===\n")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = buildArguments(url: url, kind: kind, videoHeight: videoHeight, outputDir: outputDir,
                                        isPlaylist: isPlaylist, customName: customName)

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
            await MainActor.run { self.statusLine = "失敗(終了コード \(proc.terminationStatus))" }
        }
        return success
    }

    /// yt-dlp の引数を組み立てる。
    private func buildArguments(url: String, kind: DownloadKind, videoHeight: Int?, outputDir: URL,
                                isPlaylist: Bool, customName: String) -> [String] {
        // customNameが指定されていれば、自動取得タイトルの代わりにそれを使う
        // (プレイリストはフォルダ名、単発動画はファイル名に反映)。`-o`テンプレートへの
        // リテラル埋め込みは`--restrict-filenames`の対象外(あれはyt-dlp側の`%()s`展開にしか
        // 効かない)なので、`sanitizePathComponent`で`/`等を自前で潰しておく。
        let sanitizedName = sanitizePathComponent(customName)
        let nameField = sanitizedName.isEmpty ? "%(title)s" : sanitizedName
        // プレイリストモードでは `保存先/プレイリスト名/タイトル [id].拡張子` にまとめる ―
        // そのままフォルダ単位で mytube の「フォルダを選択」に渡せる形にするため。
        let outputTemplate = isPlaylist
            ? outputDir.appendingPathComponent("\(sanitizedName.isEmpty ? "%(playlist_title)s" : sanitizedName)/%(title)s [%(id)s].%(ext)s").path
            : outputDir.appendingPathComponent("\(nameField) [%(id)s].%(ext)s").path
        var args: [String] = [
            "--newline",                 // 進捗を行単位で flush
            isPlaylist ? "--yes-playlist" : "--no-playlist",
            "--restrict-filenames",      // 安全なファイル名
            "-o", outputTemplate,
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
                "--audio-quality", "0",   // 0 = 最高音質(VBR)
            ]
        case .video:
            // 指定解像度(最大)の映像 + 最高音質を mp4 に結合。
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

    /// ユーザーが入力したダウンロード名を、`-o`テンプレートの1階層として安全に埋め込める
    /// 形に整形する。パス区切りを含んでいると意図しない階層作成/移動が起きうるため置換し、
    /// `.`/`..`だけの入力は空扱いにしてテンプレートのデフォルト値側にフォールバックさせる。
    private func sanitizePathComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return "" }
        return trimmed.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - 出力処理

    private func handleOutput(_ text: String) {
        appendLog(text)
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            // プレイリスト内の何本目かを拾う: 例 "[download] Downloading item 3 of 23"
            if let item = Self.parsePlaylistItem(String(line)) {
                playlistItemLabel = "(\(item.index)/\(item.count)) "
            }
            // 進捗パーセントを拾う: 例 "[download]  42.1% of 10.00MiB at ..."
            if let pct = Self.parsePercent(String(line)) {
                progress = pct / 100
                statusLine = playlistItemLabel + String(line).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    private func appendLog(_ text: String) {
        log += text
        if log.count > 40_000 {
            log = String(log.suffix(30_000))
        }
    }

    /// "[download] Downloading item 3 of 23" から (3, 23) を拾う。
    private static func parsePlaylistItem(_ line: String) -> (index: Int, count: Int)? {
        guard line.contains("Downloading item") else { return nil }
        let tokens = line.split(separator: " ")
        guard let itemIdx = tokens.firstIndex(of: "item"),
              itemIdx + 3 < tokens.count,
              tokens[itemIdx + 2] == "of",
              let index = Int(tokens[itemIdx + 1]),
              let count = Int(tokens[itemIdx + 3]) else { return nil }
        return (index, count)
    }

    private static func parsePercent(_ line: String) -> Double? {
        guard line.contains("[download]"), let range = line.range(of: "%") else { return nil }
        let before = line[..<range.lowerBound]
        let token = before.reversed().prefix { $0.isNumber || $0 == "." }
        let number = String(token.reversed())
        return Double(number)
    }
}
