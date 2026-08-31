import Foundation

/// リモート動画(OneDrive共有リンク)をローカルへダウンロードして保存する`@MainActor
/// ObservableObject`シングルトン(2026-08-27追加、「Local DL機能追加してほしい」という
/// 要望への対応)。mytube(Mac版)の`Core/DownloadStore.swift`のOneDrive側と同じ設計方針
/// ― 再生自体はダウンロード完了を待たずストリーミングで即座に始まり、ダウンロードは
/// 並行して進む。完了後は`playableURL(for:)`がローカルファイルを優先して返すため、以後の
/// 再生はダウンロード済みファイルから行われ、tempauth URLの期限切れ(1時間程度)の影響を
/// 受けなくなる。**Mac版のOneDrive用「ローカルに保存」トグルほどの作り込みは無い**
/// (自動保存トグル・容量上限・自動削除は無し ― MVPとしての単純さを優先し、「ダウンロード」/
/// 「削除」の単発操作のみ)。**ダウンロード開始時に`VideoItem`のメタデータを`Settings.
/// downloadedVideoInfos`へ複製・永続化する**(2026-08-27追加、「ローカルに保存した動画の
/// 一覧もほしい」という要望への対応) ― `localVideos()`がこれを使って「ローカル保存済み」
/// 一覧(`Views/LocalDownloadsView.swift`)用の`[VideoItem]`を、元の共有リンクを
/// 再スキャンせずに再構成する。
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed
    }

    @Published private(set) var states: [String: State] = [:]

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]

    /// `~/Library/Application Support/MyTubePad/downloads/` ― ユーザーが明示的に保持したい
    /// データのため、OSが気軽に破棄しうる`Caches`ではなく`Application Support`に置く
    /// (mytube Mac版の`DownloadStore`と同じ判断)。
    private let downloadsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyTubePad/downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        primeStates()
    }

    func state(for video: VideoItem) -> State {
        states[video.remoteID] ?? .notDownloaded
    }

    func localFileURL(for video: VideoItem) -> URL {
        downloadsDir.appendingPathComponent("\(video.remoteID).\(video.fileExtension)")
    }

    /// ダウンロード済みならローカルファイルのURLを、そうでなければ`video.downloadURL`
    /// (tempauth署名付きの直リンク)を返す。`PlayerView`はこれ経由でURLを取得する。
    func playableURL(for video: VideoItem) -> URL {
        if state(for: video) == .downloaded {
            let local = localFileURL(for: video)
            if FileManager.default.fileExists(atPath: local.path) {
                return local
            }
        }
        return video.downloadURL
    }

    func startDownloadIfNeeded(for video: VideoItem) {
        switch state(for: video) {
        case .downloading, .downloaded:
            return
        case .notDownloaded, .failed:
            break
        }
        states[video.remoteID] = .downloading(progress: 0)
        // 「ローカル保存済み」一覧(`Views/LocalDownloadsView.swift`)がアプリ再起動後や
        // 元の共有リンクを開き直さなくてもタイトル・チャンネルを表示できるよう、
        // ダウンロード開始時点で`VideoItem`のメタデータを複製して永続化しておく
        // (2026-08-27追加、「ローカルに保存した動画の一覧もほしい」という要望への対応)。
        saveMetadata(for: video)
        let destination = localFileURL(for: video)
        let remoteID = video.remoteID
        let task = URLSession.shared.downloadTask(with: video.downloadURL) { [weak self] tempURL, response, error in
            Task { @MainActor in
                self?.finishDownload(remoteID: remoteID, tempURL: tempURL, response: response, error: error, destination: destination)
            }
        }
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                // 完了後(`finishDownload`が`.downloaded`/`.failed`に確定させた後)に
                // 進捗KVOの最終通知が遅れて届いても上書きしないよう、まだ`.downloading`の
                // 間だけ反映する。
                if case .downloading = self?.states[remoteID] {
                    self?.states[remoteID] = .downloading(progress: fraction)
                }
            }
        }
        observations[remoteID] = observation
        tasks[remoteID] = task
        task.resume()
    }

    func cancelDownload(for video: VideoItem) {
        tasks[video.remoteID]?.cancel()
        tasks[video.remoteID] = nil
        observations[video.remoteID] = nil
        states[video.remoteID] = .notDownloaded
        removeMetadata(remoteID: video.remoteID)
    }

    /// ローカルコピーだけを削除する ― 共有元のOneDrive上のファイルには一切触れない。
    func deleteLocalCopy(for video: VideoItem) {
        try? FileManager.default.removeItem(at: localFileURL(for: video))
        states[video.remoteID] = .notDownloaded
        removeMetadata(remoteID: video.remoteID)
    }

    /// ダウンロード済みの動画をすべて削除する(2026-08-28追加、「全件削除」という要望への
    /// 対応)。進行中のダウンロードもすべてキャンセルしてから、保存先フォルダの中身を
    /// まるごと削除する ― フォルダ自体はフラットな1階層(`<remoteID>.<拡張子>`のみ)なので
    /// 個別に`deleteLocalCopy`を繰り返すより1回のディレクトリ列挙で済ませられる。
    func deleteAllLocalCopies() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        observations.removeAll()
        if let files = try? FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        states.removeAll()
        Settings.downloadedVideoInfos = [:]
    }

    /// ダウンロード済み動画の合計サイズ(「保存済み」一覧のストレージ表示用、2026-08-28追加)。
    func totalDownloadedBytes() -> Int64 {
        localVideos().reduce(0) { $0 + ($1.size ?? 0) }
    }

    /// 「ローカル保存済み」一覧(`Views/LocalDownloadsView.swift`)用 ― ダウンロード済み
    /// (実際にファイルが存在する)動画を、永続化しておいたメタデータから`VideoItem`として
    /// 再構成して返す。`downloadURL`はローカルファイルのURLをそのまま設定する(元の
    /// tempauth URLはとっくに失効しているため意味を持たず、再生は常に`playableURL(for:)`
    /// 経由でこのローカルファイルへ解決されるので、ここに何を入れても実害は無い)。
    func localVideos() -> [VideoItem] {
        Settings.downloadedVideoInfos.values.compactMap { info -> VideoItem? in
            guard states[info.remoteID] == .downloaded else { return nil }
            let localURL = downloadsDir.appendingPathComponent("\(info.remoteID).\(info.fileExtension)")
            guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
            return VideoItem(
                title: info.title,
                channel: info.channel,
                folderPath: [],
                modifiedDate: info.modifiedDate,
                downloadURL: localURL,
                remoteID: info.remoteID,
                size: info.size,
                fileExtension: info.fileExtension
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func finishDownload(remoteID: String, tempURL: URL?, response: URLResponse?, error: Error?, destination: URL) {
        observations[remoteID] = nil
        tasks[remoteID] = nil
        guard error == nil, let tempURL else {
            states[remoteID] = .failed
            removeMetadata(remoteID: remoteID)
            return
        }
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            // HTTPステータスを見ずに受け取ったファイルをそのまま保存すると、tempauth URLの
            // 期限切れ等でOneDriveが返す短いエラーレスポンスを動画本体として保存して
            // しまう(mytube Mac版の`DownloadStore.finishHTTPDownload`と同じ教訓)。
            states[remoteID] = .failed
            removeMetadata(remoteID: remoteID)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            states[remoteID] = .downloaded
        } catch {
            states[remoteID] = .failed
            removeMetadata(remoteID: remoteID)
        }
    }

    /// 起動時、ディスク上に既にダウンロード済みのファイルを`states`へ反映する。
    private func primeStates() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            let remoteID = file.deletingPathExtension().lastPathComponent
            states[remoteID] = .downloaded
        }
    }

    private func saveMetadata(for video: VideoItem) {
        var infos = Settings.downloadedVideoInfos
        infos[video.remoteID] = DownloadedVideoInfo(
            remoteID: video.remoteID, title: video.title, channel: video.channel,
            fileExtension: video.fileExtension, size: video.size, modifiedDate: video.modifiedDate
        )
        Settings.downloadedVideoInfos = infos
    }

    private func removeMetadata(remoteID: String) {
        var infos = Settings.downloadedVideoInfos
        infos.removeValue(forKey: remoteID)
        Settings.downloadedVideoInfos = infos
    }
}
