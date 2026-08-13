import Foundation

/// テキストインポートの結果。失敗分は `import-errors.log` にも書き出す。
struct ImportResult {
    var succeeded: Int
    var failed: [(line: String, message: String)]
}

@MainActor
final class PlaylistStore: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var resolvingCount = 0
    @Published var lastError: String?

    @Published var importProgress: (done: Int, total: Int)?
    @Published var importResult: ImportResult?

    let ytdlpPath = ToolLocator.locate("yt-dlp")
    let ffmpegPath = ToolLocator.locate("ffmpeg")

    private let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MyMusic", isDirectory: true)
    }()
    private var playlistFile: URL { supportDir.appendingPathComponent("playlist.json") }
    var cacheDir: URL { supportDir.appendingPathComponent("cache", isDirectory: true) }
    var importErrorLogURL: URL { supportDir.appendingPathComponent("import-errors.log") }

    init() {
        load()
    }

    private static let duplicateMessage = "この曲はすでにプレイリストにあります(重複のためスキップ)。"

    func addLink(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 貼り付けた URL 文字列がそのまま一致する場合は、解決(HTTP 取得 / yt-dlp 起動)前に弾く。
        if tracks.contains(where: { $0.sourceURL == trimmed }) {
            lastError = Self.duplicateMessage
            return
        }
        resolvingCount += 1
        Task {
            defer { resolvingCount -= 1 }
            do {
                let track = try await LinkResolver.resolve(
                    urlString: trimmed, ytdlpPath: ytdlpPath, ffmpegPath: ffmpegPath, cacheDir: cacheDir
                )
                // 解決後の再生 URL(YouTube はローカルキャッシュパス、他サイトは実 mp3 URL)で
                // 突き合わせる — 別の共有リンク形式(youtu.be vs youtube.com、共有コード違い等)で
                // 貼られた同じ曲もここで検出できる。
                guard !tracks.contains(where: { $0.audioURL == track.audioURL }) else {
                    lastError = Self.duplicateMessage
                    return
                }
                tracks.append(track)
                save()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// テキスト(1行1リンク)をまとめて解決してプレイリストに追加する。
    /// 失敗・重複したリンクはスキップして次に進み、まとめて `importResult` と `import-errors.log` に残す。
    func importLinks(_ text: String) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }

        Task {
            var succeeded = 0
            var failed: [(line: String, message: String)] = []
            var seenSourceURLs = Set(tracks.map(\.sourceURL))
            var seenAudioURLs = Set(tracks.map(\.audioURL))
            importProgress = (0, lines.count)
            for (i, line) in lines.enumerated() {
                defer { importProgress = (i + 1, lines.count) }
                if seenSourceURLs.contains(line) {
                    failed.append((line, Self.duplicateMessage))
                    continue
                }
                do {
                    let track = try await LinkResolver.resolve(
                        urlString: line, ytdlpPath: ytdlpPath, ffmpegPath: ffmpegPath, cacheDir: cacheDir
                    )
                    guard !seenAudioURLs.contains(track.audioURL) else {
                        failed.append((line, Self.duplicateMessage))
                        continue
                    }
                    tracks.append(track)
                    save()
                    seenSourceURLs.insert(line)
                    seenAudioURLs.insert(track.audioURL)
                    succeeded += 1
                } catch {
                    failed.append((line, error.localizedDescription))
                }
            }
            importProgress = nil
            importResult = ImportResult(succeeded: succeeded, failed: failed)
            if !failed.isEmpty {
                appendImportErrorLog(failed)
            }
        }
    }

    private func appendImportErrorLog(_ failed: [(line: String, message: String)]) {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var block = "=== \(timestamp) — \(failed.count)件失敗 ===\n"
        for item in failed {
            block += "\(item.line)\t\(item.message)\n"
        }
        block += "\n"
        if let existing = try? String(contentsOf: importErrorLogURL, encoding: .utf8) {
            try? (existing + block).write(to: importErrorLogURL, atomically: true, encoding: .utf8)
        } else {
            try? block.write(to: importErrorLogURL, atomically: true, encoding: .utf8)
        }
    }

    func remove(at offsets: IndexSet) {
        tracks.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: playlistFile),
              let decoded = try? JSONDecoder().decode([Track].self, from: data)
        else { return }
        // 過去に(修正前のバージョン等で)紛れ込んだ重複を再生 URL 基準で除去する。先勝ちで残す。
        var seenAudioURLs = Set<String>()
        let deduped = decoded.filter { seenAudioURLs.insert($0.audioURL).inserted }
        tracks = deduped
        if deduped.count != decoded.count {
            save()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: playlistFile)
    }
}
