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
    /// 成功時の案内(OneDrive フォルダから何曲追加したか等)。エラーとは別の色で出す。
    @Published var lastNotice: String?

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
        // OneDrive の共有リンクは1リンク=複数曲になりうるため、1リンク=1曲を前提にした
        // `LinkResolver` の経路ではなく専用のフォルダスキャンへ振り分ける。
        if OneDriveShareClient.isShareLink(trimmed) {
            addOneDriveShare(trimmed)
            return
        }
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

    /// OneDrive の共有リンク(フォルダ or 単体ファイル)をスキャンして、含まれる音声ファイルを
    /// まとめてプレイリストに追加する。
    func addOneDriveShare(_ shareURL: String) {
        resolvingCount += 1
        Task {
            defer { resolvingCount -= 1 }
            do {
                let result = try await scanOneDriveShare(shareURL)
                if result.added == 0 && result.skipped == 0 {
                    lastError = "この共有リンクには再生できる音声ファイルがありませんでした。"
                } else {
                    lastNotice = result.summary
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private struct OneDriveAddResult {
        let name: String
        let added: Int
        let skipped: Int

        var summary: String {
            var text = "OneDrive「\(name)」から \(added) 曲を追加しました"
            if skipped > 0 { text += "(既にある \(skipped) 曲はスキップ)" }
            return text
        }
    }

    /// 共有リンクをスキャンして未追加の曲だけ `tracks` に足す。同じリンクを貼り直せば、
    /// 追加済みの曲はスキップされ、共有フォルダに増えた曲だけが取り込まれる(同期のように使える)。
    private func scanOneDriveShare(_ shareURL: String) async throws -> OneDriveAddResult {
        let scanned = try await OneDriveShareClient.scanAudio(shareURL: shareURL)
        var seen = Set(tracks.map(\.dedupeKey))
        var added = 0
        var skipped = 0
        for item in scanned.items {
            let track = Track(
                sourceURL: shareURL,
                title: item.displayTitle,
                site: .oneDrive,
                audioURL: item.downloadURL,
                oneDrive: OneDriveRef(shareURL: shareURL, driveId: item.driveId, itemId: item.itemId)
            )
            guard seen.insert(track.dedupeKey).inserted else {
                skipped += 1
                continue
            }
            tracks.append(track)
            added += 1
        }
        if added > 0 { save() }
        return OneDriveAddResult(name: scanned.sourceName, added: added, skipped: skipped)
    }

    /// 再生直前に OneDrive の署名付き URL を取り直す(保存済みの URL は1時間程度で失効するため)。
    /// OneDrive 以外のトラックと、取り直しに失敗した場合はそのまま返す。
    func refreshedTrack(_ track: Track) async -> Track {
        guard let ref = track.oneDrive else { return track }
        do {
            let url = try await OneDriveShareClient.freshDownloadURL(
                shareURL: ref.shareURL, driveId: ref.driveId, itemId: ref.itemId
            )
            var updated = track
            updated.audioURL = url
            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[index].audioURL = url
                save()
            }
            return updated
        } catch {
            lastError = error.localizedDescription
            return track
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
            var seenAudioURLs = Set(tracks.map(\.dedupeKey))
            importProgress = (0, lines.count)
            for (i, line) in lines.enumerated() {
                defer { importProgress = (i + 1, lines.count) }
                // OneDrive の共有リンクは1行で複数曲になるため、こちらも専用経路へ。
                // 既に追加済みの曲はスキャン側でスキップされるので、行単位の重複チェックはしない。
                if OneDriveShareClient.isShareLink(line) {
                    do {
                        let result = try await scanOneDriveShare(line)
                        if result.added == 0 {
                            failed.append((line, result.skipped > 0
                                ? Self.duplicateMessage
                                : "この共有リンクには再生できる音声ファイルがありませんでした。"))
                        } else {
                            succeeded += result.added
                            seenSourceURLs.insert(line)
                            seenAudioURLs.formUnion(tracks.map(\.dedupeKey))
                        }
                    } catch {
                        failed.append((line, error.localizedDescription))
                    }
                    continue
                }
                if seenSourceURLs.contains(line) {
                    failed.append((line, Self.duplicateMessage))
                    continue
                }
                do {
                    let track = try await LinkResolver.resolve(
                        urlString: line, ytdlpPath: ytdlpPath, ffmpegPath: ffmpegPath, cacheDir: cacheDir
                    )
                    guard !seenAudioURLs.contains(track.dedupeKey) else {
                        failed.append((line, Self.duplicateMessage))
                        continue
                    }
                    tracks.append(track)
                    save()
                    seenSourceURLs.insert(line)
                    seenAudioURLs.insert(track.dedupeKey)
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
        let deduped = decoded.filter { seenAudioURLs.insert($0.dedupeKey).inserted }
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
