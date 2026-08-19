import Foundation

/// リモート(OneDrive共有/YouTubeプレイリスト)動画をローカルにダウンロードして保存する。
///
/// **OneDrive**: 再生自体は`PlayerEngine`が`@content.downloadUrl`(署名付きURL)を直接
/// `AVPlayer`に渡して即座にストリーミング再生する(`PlayerPaneView`参照)ため、ここでのダウンロードは
/// 「裏で並行して保存し、次回以降はローカルファイルを優先して使う」ためのもの(`URLSession`の
/// 単純なHTTP GET)。副次効果として、`@content.downloadUrl`の短い有効期限(実測1時間程度)問題も、
/// 一度ダウンロード済みの動画はローカルファイルを再生するため実質的に解消される。
/// **OneDriveは自動では始まらない**(2026-08-05、「OneDriveの場合はローカルに保存はトグルにする。
/// デフォルトではローカルダウンロードはOff」という要望への対応 ― 以前は`PlayerPaneView.play(_:)`が
/// 再生開始のたびに無条件で`startDownloadIfNeeded(for:)`を呼んでいたが、今は`Views/
/// LocalSaveToggle.swift`のトグルをONにしたときだけ呼ぶ。再生自体は上記の通りダウンロード状態と
/// 無関係にストリーミングで即座に始まるため、トグルをOFFのままにしても視聴に支障はない)。
///
/// **YouTube**: OneDriveと違い動画+音声を単純なURLで直接ストリーミングできない(高画質は
/// 映像・音声が別ストリームでAVPlayerでは合成再生できない)ため、`yt-dlp`(+`ffmpeg`での
/// 結合)でのダウンロード完了を待ってから再生する設計にしている ― `PlayerPaneView`は
/// `.downloaded`になるまで`PlayerEngine`にURLを渡さない(`isDownloaded`が`false`の間は
/// 「ダウンロード中」表示に留める)。
///
/// `PlayerPaneView`が動画の再生を開始するたびに`startDownloadIfNeeded(for:)`を呼ぶことで、
/// OneDriveは「再生しながら裏でダウンロードする」、YouTubeは「ダウンロードしてから再生する」を
/// それぞれ実現する。
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(String)
    }

    /// キーは`VideoItem.remoteID`。ローカル動画(remoteIDがnil)はここに現れない。
    @Published private(set) var states: [String: State] = [:]

    private let downloadsDir: URL
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    /// YouTube用(`yt-dlp`をProcessとして起動するダウンロード)。`tasks`(OneDriveの
    /// `URLSessionDownloadTask`)とは別に保持する ― 停止・完了時に`terminate()`できるようにするため。
    private var youtubeProcesses: [String: Process] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // `~/Library/Caches`ではなく`Application Support`に置く ― ユーザーが明示的に
        // 保存したい動画であり、`ThumbnailStore`のサムネイルのようにOSが気軽に破棄してよい
        // キャッシュとは性質が異なるため(ディスク逼迫時にmacOSが自動削除しうるCachesは不向き)。
        downloadsDir = base.appendingPathComponent("MyTube/downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        // 前回起動後に上限(`Settings.maxCacheBytes`)を引き下げていた場合にも反映されるよう、
        // 起動時にも一度チェックする(ダウンロード完了時だけでなく)。
        enforceCacheLimit()
    }

    /// ダウンロード済みならローカルファイルのURL、そうでなければ`video.url`(ローカル動画なら
    /// そのまま元のパス、リモート動画ならストリーミング用の署名付きURL)を返す。
    /// `PlayerPaneView`が再生用URLとして常にこれを経由する。
    func playableURL(for video: VideoItem) -> URL {
        guard video.isRemote, state(for: video) == .downloaded else { return video.url }
        return localFileURL(for: video)
    }

    /// **`states`へは書き込まない**(2026-08-06、パフォーマンス改善 ― 以前はここでキャッシュ
    /// ミス時に`states[remoteID] = .downloaded`と書き込んでいたが、この関数は
    /// `VideoThumbnailView.body`から直接(`.task`等を介さず)同期的に呼ばれるため、
    /// グリッドに前回セッションでダウンロード済みのリモート動画が多数並ぶ初回表示・
    /// スクロール時に、SwiftUIのビュー更新中に`@Published var states`を変更することになり
    /// (SwiftUIが警告する「Publishing changes from within view updates」)、`DownloadStore.shared`を
    /// 監視している他の全セル(`VideoThumbnailView`はすべて`@ObservedObject`で購読)の
    /// 再描画をそのたびに誘発していた ― 画面に見えている枚数ぶん連鎖的に余分な再描画パスが
    /// 走り、体感の「もたつき」の一因になっていた。ディスク上に既にあるダウンロード済みリモート
    /// 動画の発見は`primeStates(for:)`(下記)がソースのスキャン直後にまとめて1回で行うように
    /// 移し、ここは`states`の読み取り専用にした(まだ`primeStates`が終わっていない一瞬だけ
    /// ディスクを直接見るフォールバックは残すが、書き込みはしない)。
    func state(for video: VideoItem) -> State {
        guard let remoteID = video.remoteID else { return .notDownloaded }
        if let cached = states[remoteID] { return cached }
        return FileManager.default.fileExists(atPath: localFileURL(for: video).path) ? .downloaded : .notDownloaded
    }

    /// ソースの動画一覧が(再)スキャンされた直後に呼ぶ ― 前回のセッションで既にダウンロード
    /// 済みのリモート動画の状態を、`state(for:)`が呼ばれるたび(=セルの描画のたび)にではなく
    /// まとめて1回のディスクI/O走査+1回だけの`states`更新で先読みする(2026-08-06追加、
    /// 上記`state(for:)`のドキュメント参照)。`states`への代入は最後に1回だけ行い
    /// (見つかった件数ぶん代入を繰り返すと、その数だけ`@Published`の変更通知が飛んでしまうため)、
    /// `objectWillChange`の発火を1回に抑える。
    func primeStates(for videos: [VideoItem]) {
        let candidates: [(remoteID: String, path: String)] = videos.compactMap { video in
            guard let remoteID = video.remoteID, states[remoteID] == nil else { return nil }
            return (remoteID, localFileURL(for: video).path)
        }
        guard !candidates.isEmpty else { return }
        let start = DispatchTime.now()
        Task.detached(priority: .utility) { [weak self] in
            var discovered: [String: State] = [:]
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                discovered[candidate.remoteID] = .downloaded
            }
            Log.download.info("primeStates: \(candidates.count)件確認、\(discovered.count)件がダウンロード済み (\(Log.elapsedMs(since: start), format: .fixed(precision: 1))ms)")
            guard !discovered.isEmpty, let self else { return }
            await MainActor.run { [discovered] in
                var updated = self.states
                for (remoteID, state) in discovered where updated[remoteID] == nil {
                    updated[remoteID] = state
                }
                self.states = updated
            }
        }
    }

    func isDownloaded(_ video: VideoItem) -> Bool {
        state(for: video) == .downloaded
    }

    /// ダウンロード済みのローカルコピーの実際のファイルサイズ(2026-08-05追加、「ローカルにDLした
    /// サイズを各ビデオに表示してほしい」という要望への対応)。未ダウンロード/失敗中は`nil`。
    /// `localCacheSummary()`と同じくキャッシュはせず毎回`stat`する(1ファイルぶんの軽い
    /// 呼び出しで、ダウンロード完了直後・削除直後に古いサイズを返す心配もないため)。
    func localFileSize(for video: VideoItem) -> Int64? {
        guard video.isRemote, state(for: video) == .downloaded else { return nil }
        guard let values = try? localFileURL(for: video).resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return nil }
        return Int64(size)
    }

    /// ローカルに保存済みのコピーだけをゴミ箱へ移動する(リポジトリ規約通りハード削除はしない)。
    /// 共有元のOneDrive上のファイルには一切影響しない ― 削除後は`playableURL`が再び
    /// ストリーミング用の署名付きURLを返すようになるだけで、`VideoItem`自体は一覧に残る
    /// (ローカル動画本体は直接削除する手段を持たず、`VideoCardView`ではFinderで表示する
    /// だけなのとは対照的)。
    func deleteLocalCopy(for video: VideoItem) async throws {
        guard let remoteID = video.remoteID, state(for: video) == .downloaded else { return }
        let fileURL = localFileURL(for: video)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
        }.value
        states[remoteID] = .notDownloaded
    }

    /// ダウンロード済みファイルの件数・合計サイズ(2026-08-05追加、`deleteAllLocalCopies()`の
    /// 確認ダイアログに出す用)。`downloadsDir`直下はフラット(サブフォルダを持たない、
    /// `localFileURL(for:)`参照)なので`contentsOfDirectory`1回で足りる。
    func localCacheSummary() -> (count: Int, totalBytes: Int64) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: downloadsDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return (0, 0) }
        let totalBytes = urls.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
        return (urls.count, totalBytes)
    }

    /// ローカルにダウンロード済みのコピーを**一気に**ゴミ箱へ移動する(2026-08-05追加、
    /// 「ローカルにDLしたキャッシュを一気に削除する機能」という要望への対応)。
    /// `deleteLocalCopy(for:)`を動画ごとに繰り返すのではなく`downloadsDir`フォルダ自体を
    /// まるごとゴミ箱へ移動してから空フォルダを作り直す ― ファイル数が多くても1回の
    /// ファイル操作で済み、`localFileURL(for:)`の命名規則(`<remoteID>.<拡張子>`)を
    /// 個別に組み立てる必要もない。進行中のダウンロード(`URLSessionDownloadTask`/
    /// `yt-dlp`の`Process`)はフォルダ削除前に止める ― 削除直後に書き込みが再開されて
    /// 宙に浮いたファイルが復活するのを防ぐため。共有元のOneDrive上のファイル/YouTube上の
    /// 動画には一切影響しない ― 削除後は全ての`state(for:)`が`.notDownloaded`に戻るだけで、
    /// `VideoItem`自体は一覧に残る。
    func deleteAllLocalCopies() async throws {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        progressObservations.removeAll()
        for process in youtubeProcesses.values { process.terminate() }
        youtubeProcesses.removeAll()

        let dir = downloadsDir
        try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: dir.path) else { return }
            try FileManager.default.trashItem(at: dir, resultingItemURL: nil)
        }.value
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        states.removeAll()
    }

    /// キャッシュの合計サイズが`Settings.maxCacheBytes`(既定5GB)を超えていたら、更新日時の
    /// 古いファイルから順にゴミ箱へ送って上限以下に収める(2026-08-05追加、「ローカルキャッシュの
    /// 最大値を設定したい。5Gを超えたら古いものを削除する」という要望への対応)。ダウンロード
    /// 完了のたびと、起動時(`init`)・上限値の変更時(`TopBarView`のキャッシュ設定ポップオーバー)に
    /// 呼ぶ。ちょうどダウンロードし終えたファイルは更新日時が最も新しいため、自然と削除対象の
    /// 優先度が最も低くなる(直近再生した動画から真っ先に消えることはない)。ファイルI/Oは
    /// `Task.detached`でメインスレッド外へ逃がし、完了後に該当`states`だけメインスレッドで
    /// `.notDownloaded`へ書き戻す。
    func enforceCacheLimit() {
        let limit = Settings.maxCacheBytes
        let dir = downloadsDir
        Task.detached(priority: .utility) { [weak self] in
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            ) else { return }

            var entries = urls.compactMap { url -> (url: URL, size: Int64, date: Date)? in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                else { return nil }
                return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
            entries.sort { $0.date < $1.date }

            var total = entries.reduce(Int64(0)) { $0 + $1.size }
            guard total > limit else { return }

            var evictedRemoteIDs: [String] = []
            for entry in entries {
                guard total > limit else { break }
                guard (try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)) != nil else { continue }
                total -= entry.size
                evictedRemoteIDs.append(entry.url.deletingPathExtension().lastPathComponent)
            }

            guard !evictedRemoteIDs.isEmpty else { return }
            await MainActor.run { [weak self, evictedRemoteIDs] in
                for remoteID in evictedRemoteIDs {
                    self?.states[remoteID] = .notDownloaded
                }
            }
        }
    }

    /// OneDriveの「ローカルに保存」トグルをOFFにした際の統一エントリポイント
    /// (2026-08-05追加、`Views/LocalSaveToggle.swift`参照)。ダウンロード中なら
    /// `cancelDownload(remoteID:)`で中断し、ダウンロード済みなら`deleteLocalCopy(for:)`と
    /// 同じくゴミ箱へ移動する。呼び出し元は確認ダイアログでユーザーがYesを選んだ後に呼ぶ。
    func disableLocalSave(for video: VideoItem) async throws {
        guard video.remoteID != nil else { return }
        switch state(for: video) {
        case .downloading:
            cancelDownload(for: video)
        case .downloaded:
            try await deleteLocalCopy(for: video)
        case .notDownloaded, .failed:
            break
        }
    }

    /// 進行中のダウンロード(OneDriveの`URLSessionDownloadTask`/YouTubeの`yt-dlp` `Process`)を
    /// 1件だけ中断し、`.notDownloaded`に戻す。`deleteAllLocalCopies()`が全件まとめて行っている
    /// 処理の単体版(2026-08-05追加)。`terminationHandler`は明示的に`nil`にしてから
    /// `terminate()`する ― 既存のハンドラのまま呼ぶと、プロセス終了が非同期に届いた際に
    /// (既にこちらで`.notDownloaded`へ戻した後の)状態を`.failed`で上書きしてしまうため。
    private func cancelDownload(for video: VideoItem) {
        guard let remoteID = video.remoteID else { return }
        tasks[remoteID]?.cancel()
        tasks[remoteID] = nil
        progressObservations[remoteID] = nil
        if let proc = youtubeProcesses[remoteID] {
            proc.terminationHandler = nil
            proc.terminate()
            youtubeProcesses[remoteID] = nil
        }
        states[remoteID] = .notDownloaded
    }

    /// 既にダウンロード中/ダウンロード済みなら何もしない。ローカル動画(`remoteID == nil`)は無視する。
    func startDownloadIfNeeded(for video: VideoItem) {
        guard let remoteID = video.remoteID else { return }
        switch state(for: video) {
        case .downloaded, .downloading:
            return
        case .notDownloaded, .failed:
            break
        }

        Log.download.info("開始: \(video.title, privacy: .public) (\(video.remoteKind?.displayName ?? "?", privacy: .public))")
        states[remoteID] = .downloading(progress: 0)
        if video.remoteKind == .youtube {
            startYouTubeDownload(remoteID: remoteID, video: video)
        } else {
            startHTTPDownload(remoteID: remoteID, video: video)
        }
    }

    /// OneDrive用: `@content.downloadUrl`(署名付きの直接ダウンロード可能なURL)への単純なHTTP GET。
    private func startHTTPDownload(remoteID: String, video: VideoItem) {
        let destination = localFileURL(for: video)
        let task = URLSession.shared.downloadTask(with: video.url) { [weak self] tempURL, response, error in
            Task { @MainActor in
                self?.finishHTTPDownload(remoteID: remoteID, tempURL: tempURL, response: response, destination: destination, error: error)
            }
        }
        progressObservations[remoteID] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                // ダウンロード完了後(`finishHTTPDownload`が`.downloaded`/`.failed`に既に書き換えた後)に
                // 遅れて発火するKVO通知で状態を`.downloading`に巻き戻さないようにする。
                guard case .downloading = self?.states[remoteID] else { return }
                self?.states[remoteID] = .downloading(progress: fraction)
            }
        }
        tasks[remoteID] = task
        task.resume()
    }

    private func finishHTTPDownload(remoteID: String, tempURL: URL?, response: URLResponse?, destination: URL, error: Error?) {
        progressObservations[remoteID] = nil
        tasks[remoteID] = nil

        if let error {
            // キャンセルはユーザー操作の結果(将来UIを追加する場合に備え、明示的に無視する)であり
            // 「失敗」として表示すべきエラーではない。
            if (error as NSError).code == NSURLErrorCancelled { return }
            states[remoteID] = .failed(error.localizedDescription)
            return
        }
        guard let tempURL else {
            states[remoteID] = .failed("ダウンロードに失敗しました")
            return
        }
        // `URLSession`はHTTPステータスが4xx/5xxでも`error`をnilのまま返す(ネットワーク層の
        // エラーではないため)。ステータスを見ずに`tempURL`をそのまま保存すると、
        // `@content.downloadUrl`が期限切れ・アクセス拒否だった場合にOneDriveが返す短い
        // エラーレスポンス(HTML/JSON)をあたかも動画本体のように保存してしまい、
        // 「ダウンロード済みなのにサイズが極端に小さく実際の動画と食い違う」不具合になる
        // (2026-08-05、ユーザー報告で発覚 ― ダウンロードフォルダに数十バイトしかない
        // `.mp4`が見つかった)。
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            states[remoteID] = .failed("ダウンロードに失敗しました(HTTP \(http.statusCode))")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            states[remoteID] = .downloaded
            Log.download.info("完了(OneDrive): \(remoteID, privacy: .public)")
            enforceCacheLimit()
        } catch {
            states[remoteID] = .failed(error.localizedDescription)
            Log.download.error("失敗(OneDrive): \(remoteID, privacy: .public) \(error.localizedDescription, privacy: .public)")
        }
    }

    /// YouTube用: `yt-dlp`を`Process`として起動し、映像+音声を`ffmpeg`でmp4に結合しながら
    /// `destination`へ直接書き出す(`downloader/Sources/Downloader/YtDlpManager`と同じ
    /// 「`--newline`の進捗行をパースする」方式)。1080p以下の最高画質を狙い、無ければ
    /// 単一フォーマットの`best`にフォールバックする。
    ///
    /// **`vcodec^=avc1`(H.264)を明示的に要求する**(2026-08-05追加 ― コーデック指定なしの
    /// `bestvideo`だと、YouTubeが同じ解像度でもVP9/AV1(webmコンテナ)の映像ストリームを
    /// 「best」として返すことが多く、`--merge-output-format mp4`でmp4コンテナに詰め直しても
    /// 中身のコーデック自体はVP9/AV1のまま ― `AVFoundation`/`AVPlayer`はVP9・AV1の
    /// デコードに対応していないため、映像トラックだけデコードできず「音は出るが映像が出ない」
    /// (音声はOpus/AACで対応コーデックのため問題なく再生される)という不具合になっていた。
    /// `[vcodec^=avc1]`でH.264ストリームに絞ることで解消する ― YouTubeは1080p以下なら
    /// ほぼ必ずH.264版も配信しているため、実用上この制約でダウンロードできなくなることは稀。
    /// 万一無い場合(`/`区切りのフォールバック)は単一ファイル形式の`best`(itag 18/22等、
    /// 昔からある映像+音声一体のH.264ストリーム)まで下げる。
    private func startYouTubeDownload(remoteID: String, video: VideoItem) {
        guard let ytdlp = ToolLocator.locate("yt-dlp") else {
            states[remoteID] = .failed("yt-dlpが見つかりません(brew install yt-dlpでインストールしてください)")
            return
        }
        let destination = localFileURL(for: video)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        var args = [
            "--newline", "--no-warnings", "--no-playlist",
            "-f", "bestvideo[vcodec^=avc1][height<=1080]+bestaudio[acodec^=mp4a]/best[vcodec^=avc1][height<=1080]/best[vcodec^=avc1]/best",
            "--merge-output-format", "mp4",
            "-o", destination.path,
        ]
        if let ffmpeg = ToolLocator.locate("ffmpeg") {
            args += ["--ffmpeg-location", ffmpeg]
        }
        args.append(video.url.absoluteString)
        proc.arguments = args
        // `yt-dlp`自身はフルパス(`ytdlp`)で直接execするため`PATH`が無くても起動できるが、
        // 内部でYouTubeのJSチャレンジ解決に`deno`(Homebrewでインストール)を`PATH`検索で
        // 探して起動する ― GUIアプリをFinder/Dockから起動した場合、継承される`PATH`が
        // 最小限(`/usr/bin:/bin:/usr/sbin:/sbin`程度)で`/opt/homebrew/bin`を含まないため、
        // `deno`が見つからずJSチャレンジを解けずに終了コード1で失敗していた(2026-08-14、
        // 「YoutubeのDLができなくなっています」という報告で発覚 ― yt-dlp/YouTube側の
        // 変更でJSチャレンジ解決が必須になったことがこの不具合を顕在化させたとみられる)。
        // `ToolLocator.searchDirs`と同じ既知のHomebrewパスを明示的な`PATH`として渡すことで、
        // 起動元(Finder/Dock/Terminal)によらず`deno`/`node`を確実に見つけられるようにする。
        var environment = ProcessInfo.processInfo.environment
        let homebrewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
        environment["PATH"] = homebrewPaths + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        proc.environment = environment

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            guard let pct = Self.parseDownloadPercent(text) else { return }
            Task { @MainActor in
                guard case .downloading = self?.states[remoteID] else { return }
                self?.states[remoteID] = .downloading(progress: pct / 100)
            }
        }

        do {
            try proc.run()
        } catch {
            states[remoteID] = .failed("yt-dlpの起動に失敗しました: \(error.localizedDescription)")
            return
        }
        youtubeProcesses[remoteID] = proc

        proc.terminationHandler = { [weak self] terminated in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.youtubeProcesses[remoteID] = nil
                if terminated.terminationStatus == 0, FileManager.default.fileExists(atPath: destination.path) {
                    self?.states[remoteID] = .downloaded
                    Log.download.info("完了(YouTube): \(remoteID, privacy: .public)")
                    self?.enforceCacheLimit()
                } else {
                    self?.states[remoteID] = .failed("ダウンロードに失敗しました(yt-dlp終了コード \(terminated.terminationStatus))")
                    Log.download.error("失敗(YouTube): \(remoteID, privacy: .public) 終了コード \(terminated.terminationStatus)")
                }
            }
        }
    }

    /// yt-dlpの`--newline`進捗行(例: "[download]  42.1% of ~10.00MiB at 1.20MiB/s ETA 00:10")から
    /// パーセント値を拾う(`downloader`の`YtDlpManager.parsePercent`と同じロジック)。
    private nonisolated static func parseDownloadPercent(_ text: String) -> Double? {
        var result: Double?
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard line.contains("[download]"), let range = line.range(of: "%") else { continue }
            let before = line[..<range.lowerBound]
            let token = before.reversed().prefix { $0.isNumber || $0 == "." }
            if let value = Double(String(token.reversed())) { result = value }
        }
        return result
    }

    /// ファイル名は`<remoteID>.<拡張子>`。OneDriveのアイテムID(`!`を含む)はmacOSのファイル名
    /// として有効な文字だが、念のため`/`だけ安全な文字に置き換える。
    private func localFileURL(for video: VideoItem) -> URL {
        guard let remoteID = video.remoteID else { return video.url }
        let safeID = remoteID.replacingOccurrences(of: "/", with: "_")
        return downloadsDir.appendingPathComponent("\(safeID).\(video.fileExtension)")
    }
}
