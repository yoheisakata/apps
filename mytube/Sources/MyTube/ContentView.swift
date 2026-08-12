import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    /// ローカルフォルダ・OneDrive共有リンクは複数同時に開ける(2026-08-04〜、「開いたものは
    /// 明示的に閉じるまでロードしたままにしたい」という要望に対応)。それぞれ独立した配列で
    /// 持ち、`allVideos`(下記)で合算する。`openFolder(_:)`/`openRemote(name:shareURL:)`は
    /// 既存の配列を全部置き換えるのではなく、対象の要素だけを追加・更新する。
    @State private var localSources: [LocalSource] = []
    @State private var remoteSources: [RemoteSource] = []
    /// フォルダを切り替えても(サイドバーが手動で再表示されていれば視聴中でも操作できる、
    /// `isSidebarCollapsed`参照)`selectedVideo`はここでは触らない(以前は
    /// `.onChange(of: selectedChannel)`で`selectedVideo = nil`にしてホーム画面へ強制的に
    /// 戻していたが、`WatchView.onDisappear`(当時の名称)が`engine.stop()`するため再生が
    /// 止まってしまう不具合だった、2026-08-04削除)。選択変更は`filteredVideos`
    /// (`upNextList`・オートプレイのキュー双方の元)を絞り込むだけで、再生中の動画そのものには
    /// 影響しない。
    /// サイドバーのフォルダツリー(`Core/FolderTree.swift`)でどのノードを選んでいるか ―
    /// `nil`なら「すべての動画」(全ソース合算)。ソースをまたいだ同名サブフォルダを
    /// 区別するため`sourceID`も持つ(単なる`channel`文字列だけでは一意に決まらない)。
    @State private var selectedNode: SidebarSelection?
    @State private var selectedVideo: VideoItem?
    /// フォルダツリーサイドバーを隠しているか(2026-08-06追加、「再生プレーヤーの下のリストを
    /// 削除したら、画面がもう少し大きくなるのでは?」という提案への回答 ― 実際にはプレイヤーは
    /// デフォルトウィンドウ幅では横幅で頭打ちになっており、下のグリッドではなくこの左サイドバー
    /// (幅220〜260pt)を隠す方が効くと判断した。動画を開くたびに自動で`true`にし、閉じたら
    /// `false`に戻す(`.onChange(of: selectedVideo)`参照)。`TopBarView`左端のボタンでいつでも
    /// 手動で表示・非表示を切り替えられる ― 視聴中でも別のフォルダに切り替えたい場合はそちらを使う。
    @State private var isSidebarCollapsed = false
    /// ミニプレーヤーモード(2026-08-07追加、「常に最前面表示のミニプレーヤーモード」という
    /// 要望への対応)。オンの間は`TopBarView`/`SidebarView`を描画せず、`PlayerPaneView`にも
    /// 直接束縛して動画のみのコンパクトな`body`(`miniPlayerBody`)へ切り替えさせる ―
    /// ツリーの他の部分(`.onAppear`の`restoreOpenSources()`等)は残したまま`TopBarView`/
    /// `SidebarView`の描画だけを止めることで、モードの往復のたびに再スキャン・再取得が
    /// 走らないようにしている。ウィンドウを実際に小さく・常に最前面にする処理は
    /// `WindowLevelAccessor`(本ファイル末尾)が`.background`経由でNSWindowを直接操作する。
    @State private var isMiniPlayerMode = false
    @State private var searchText = ""
    @State private var selectedSortOption: SortOption = .titleAscending
    @State private var homeViewMode: HomeViewMode = Settings.homeViewMode
    @State private var minLengthSecondsText = ""
    @State private var maxLengthSecondsText = ""
    /// `ThumbnailStore.durationCache`(NSCache)はメモリ逼迫時に破棄されうるため、フィルター中の
    /// 動画の長さは通常の Dictionary に保持する(破棄されるとフィルター結果から動画が消えてしまうため)。
    @State private var videoDurations: [URL: TimeInterval] = [:]
    @State private var isMeasuringDurations = false
    @State private var isDropTargeted = false

    @State private var showsShareLinkSheet = false
    @State private var sharedLinkBookmarks: [SharedLinkBookmark] = []
    @State private var shareLoadError: String?
    @State private var showsYouTubeSheet = false
    @State private var youtubePlaylistBookmarks: [SharedLinkBookmark] = []
    @State private var youtubeLoadError: String?

    private var allVideos: [VideoItem] {
        localSources.flatMap(\.videos) + remoteSources.flatMap(\.videos)
    }

    private var hasAnySource: Bool { !localSources.isEmpty || !remoteSources.isEmpty }

    /// 何も表示するものがまだ無いのに、どれかの読み込みが進行中(ローディング画面を出す条件)。
    /// 既に表示できる動画がある状態で別のソースを追加読み込み中のときは、グリッドを
    /// ローディング表示で覆わず今ある分をそのまま見せる(新しい分は読み込み完了次第追加される)。
    private var isLoadingWithNothingToShow: Bool {
        allVideos.isEmpty && (localSources.contains { $0.isScanning } || remoteSources.contains { $0.isLoading })
    }

    private var minLengthSeconds: Int? { Int(minLengthSecondsText) }
    private var maxLengthSeconds: Int? { Int(maxLengthSecondsText) }
    private var isLengthFilterActive: Bool { minLengthSeconds != nil || maxLengthSeconds != nil }

    /// サイドバーでノードが選択されていれば、そのソースの動画だけを対象に`folderPath`の
    /// 前方一致で絞り込む(祖先フォルダを選んだら配下も全部含む、explorerと同じ挙動)。
    /// 未選択(`nil`)なら全ソース合算(`allVideos`)がそのまま対象。
    private var filteredVideos: [VideoItem] {
        var videos: [VideoItem]
        if let selectedNode {
            let sourceVideos = localSources.first(where: { $0.id == selectedNode.sourceID })?.videos
                ?? remoteSources.first(where: { $0.id == selectedNode.sourceID })?.videos
                ?? []
            videos = sourceVideos.filter { $0.folderPath.starts(with: selectedNode.folderPath) }
        } else {
            videos = allVideos
        }
        if isLengthFilterActive {
            videos = videos.filter { video in
                guard let duration = videoDurations[video.url] else { return false }
                if let minLengthSeconds, duration < Double(minLengthSeconds) { return false }
                if let maxLengthSeconds, duration > Double(maxLengthSeconds) { return false }
                return true
            }
        }
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            videos = videos.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
        }
        return videos.sorted(by: selectedSortOption.areInIncreasingOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isMiniPlayerMode {
                TopBarView(
                    searchText: $searchText,
                    selectedSortOption: $selectedSortOption,
                    homeViewMode: $homeViewMode,
                    minLengthSecondsText: $minLengthSecondsText,
                    maxLengthSecondsText: $maxLengthSecondsText,
                    isSidebarCollapsed: $isSidebarCollapsed,
                    isMeasuringDurations: isMeasuringDurations,
                    onChooseFolder: chooseFolder,
                    onOpenShareLink: {
                        shareLoadError = nil
                        showsShareLinkSheet = true
                    },
                    onOpenYouTubePlaylist: {
                        youtubeLoadError = nil
                        showsYouTubeSheet = true
                    },
                    onGoHome: { selectedVideo = nil },
                    isMiniPlayerAvailable: selectedVideo != nil,
                    onEnterMiniPlayer: { isMiniPlayerMode = true }
                )
                Divider()
            }
            HStack(spacing: 0) {
                if !isSidebarCollapsed && !isMiniPlayerMode {
                    SidebarView(
                        localSources: localSources,
                        remoteSources: remoteSources,
                        selectedNode: $selectedNode,
                        onUnload: unloadSource
                    )
                    Divider()
                }
                // 動画選択中は`PlayerPaneView`、未選択なら`HomeVideosView`(2026-08-06、
                // 「再生中は一旦Grid消したらどうなる?」という提案を実際に試した結果 ―
                // プレイヤーは横幅で頭打ちのため、下のグリッドを隠しても`playerArea`自体は
                // 大きくならないが、`upNextList`(次の動画)が画面下まで使えるようになり
                // YouTubeの視聴ページに近い見た目になる、という理由で採用した。
                // 2026-08-05時点では「動画を見ながらグリッドから他の動画も探せる」ことを
                // 理由に常時表示にしていた(旧`WatchView`からの統合の動機)が、今回は
                // その方針を明示的に変更している ― 動画を探すのは`upNextList`か、
                // プレイヤーを閉じてグリッドへ戻る形になる。
                VStack(spacing: 0) {
                    if let selectedVideo {
                        PlayerPaneView(
                            video: selectedVideo,
                            queue: filteredVideos,
                            isMiniPlayerMode: $isMiniPlayerMode,
                            onSelect: { self.selectedVideo = $0 },
                            onClose: { self.selectedVideo = nil },
                            onRetry: retryPlayback
                        )
                    } else {
                        HomeVideosView(
                            videos: filteredVideos,
                            hasFolder: hasAnySource,
                            isScanning: isLoadingWithNothingToShow,
                            viewMode: homeViewMode,
                            onSelect: { selectedVideo = $0 }
                        )
                    }
                }
                // ミニプレーヤーモード中は`.infinity`で広げない ― `PlayerPaneView.miniPlayerBody`の
                // 小さいidealサイズがそのままこのVStack・上位のHStack/VStackへ伝わり、ウィンドウが
                // 追従して縮む(`isMiniPlayerMode`のドキュメント参照)。
                .frame(maxWidth: isMiniPlayerMode ? nil : .infinity, maxHeight: isMiniPlayerMode ? nil : .infinity)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(Color.accentColor, lineWidth: 4)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        }
        .background(WindowLevelAccessor(isFloatingOnTop: isMiniPlayerMode, onZoomButtonClicked: { isMiniPlayerMode = false }))
        .onAppear {
            restoreOpenSources()
            sharedLinkBookmarks = Settings.sharedLinkBookmarks
            youtubePlaylistBookmarks = Settings.youtubePlaylistBookmarks
        }
        .onChange(of: minLengthSecondsText) { _ in ensureDurationsLoaded() }
        .onChange(of: maxLengthSecondsText) { _ in ensureDurationsLoaded() }
        .onChange(of: homeViewMode) { newValue in Settings.homeViewMode = newValue }
        // 動画を開いたら自動でサイドバーを隠し、閉じたら自動で戻す(`isSidebarCollapsed`の
        // ドキュメント参照)。動画から動画への切り替え(どちらも非nil)でも発火するが、
        // その場合も`newValue != nil`は変わらず`true`のままなので、手動でサイドバーを
        // 再表示していた場合は次の動画に切り替えたタイミングで再び隠れる(視聴中は隠れた
        // ままにする、という単純な規則を優先した)。
        .onChange(of: selectedVideo) { newValue in
            isSidebarCollapsed = newValue != nil
            // プレイヤーを閉じたらミニプレーヤーモードも解除する(閉じるボタンは
            // `PlayerPaneView.miniPlayerBody`側で`isMiniPlayerMode = false`してから
            // `onClose`を呼んでいるが、他の経路(ホームロゴ等)で`selectedVideo`が
            // `nil`になった場合の保険)。
            if newValue == nil { isMiniPlayerMode = false }
        }
        .sheet(isPresented: $showsShareLinkSheet) {
            OpenRemoteLinkSheet(
                isPresented: $showsShareLinkSheet,
                title: "OneDriveリンクを開く",
                urlPlaceholder: "https://1drv.ms/...",
                bookmarks: sharedLinkBookmarks,
                isLoading: remoteSources.contains { $0.kind == .oneDrive && $0.isLoading },
                errorMessage: shareLoadError,
                onSelect: { openRemote(name: $0.name, shareURL: $0.url, kind: .oneDrive) },
                onDelete: deleteOneDriveBookmark,
                onAddAndLoad: addOneDriveBookmarkAndLoad
            )
        }
        .sheet(isPresented: $showsYouTubeSheet) {
            OpenRemoteLinkSheet(
                isPresented: $showsYouTubeSheet,
                title: "YouTubeプレイリストを開く",
                urlPlaceholder: "https://www.youtube.com/playlist?list=...",
                showsNameField: false,
                bookmarks: youtubePlaylistBookmarks,
                isLoading: remoteSources.contains { $0.kind == .youtube && $0.isLoading },
                errorMessage: youtubeLoadError,
                onSelect: { openRemote(name: $0.name, shareURL: $0.url, kind: .youtube) },
                onDelete: deleteYouTubeBookmark,
                onAddAndLoad: addYouTubeBookmarkAndLoad
            )
        }
    }

    /// 前回終了時に開いていたローカルフォルダ・共有リンクを復元し、さらに**登録済み**の
    /// 共有リンクブックマーク(`Settings.sharedLinkBookmarks`)も毎回自動で開く(2026-08-04〜、
    /// 「登録したリンクは起動時にロードしてほしい」という要望に対応。以前は前回終了時に
    /// 開いていたものだけが復元され、登録だけして閉じていたリンクは手動で選ぶまで
    /// 開かれなかった)。ブックマークと「前回開いていたリンク」でURLが重複する場合は
    /// 二重に開かないよう`seenURLs`でde-dupeする(ブックマーク名を優先、ブックマークに
    /// 無い=登録せず開いていただけの単発リンクも従来通り復元する)。
    private func restoreOpenSources() {
        for path in Settings.openLocalFolders {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            openFolder(URL(fileURLWithPath: path))
        }

        var seenOneDriveURLs = Set<String>()
        for bookmark in Settings.sharedLinkBookmarks {
            seenOneDriveURLs.insert(bookmark.url)
            openRemote(name: bookmark.name, shareURL: bookmark.url, kind: .oneDrive)
        }
        for link in Settings.openRemoteLinks where !seenOneDriveURLs.contains(link.url) {
            openRemote(name: link.name, shareURL: link.url, kind: .oneDrive)
        }

        var seenYouTubeURLs = Set<String>()
        for bookmark in Settings.youtubePlaylistBookmarks {
            seenYouTubeURLs.insert(bookmark.url)
            openRemote(name: bookmark.name, shareURL: bookmark.url, kind: .youtube)
        }
        for link in Settings.openYouTubePlaylists where !seenYouTubeURLs.contains(link.url) {
            openRemote(name: link.name, shareURL: link.url, kind: .youtube)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "動画が入ったフォルダを選んでください(サブフォルダも読み込みます)"
        if let start = localSources.last?.url {
            panel.directoryURL = start
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    /// フォルダを画面にドラッグ&ドロップして読み込む。複数ドロップされた場合は
    /// 最初に見つかったフォルダだけを使う(`chooseFolder` の allowsMultipleSelection = false
    /// と挙動を揃える)。ファイル(フォルダでないもの)がドロップされた場合は何もしない。
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
                openFolder(url)
            }
        }
        return true
    }

    /// 既に同じパスを開いていれば再スキャン(中身の更新)、無ければ新規追加する
    /// (`LocalSource.id` = パス文字列で重複判定)。既存の他のソースには影響しない。
    private func openFolder(_ url: URL) {
        let path = url.path
        if let index = localSources.firstIndex(where: { $0.id == path }) {
            localSources[index].isScanning = true
        } else {
            localSources.append(LocalSource(id: path, url: url, isScanning: true))
        }
        selectedNode = nil
        persistOpenSources()

        Task.detached(priority: .userInitiated) {
            let items = VideoScanner.scan(root: url)
            await MainActor.run {
                guard let index = localSources.firstIndex(where: { $0.id == path }) else { return }
                localSources[index].videos = items
                localSources[index].isScanning = false
                ensureDurationsLoaded()
            }
        }
    }

    private func closeLocalSource(_ source: LocalSource) {
        localSources.removeAll { $0.id == source.id }
        if selectedNode?.sourceID == source.id { selectedNode = nil }
        persistOpenSources()
    }

    /// `SidebarView`のツリーの✕ボタンから呼ばれる ― ローカル/リモートどちらのソースIDかを
    /// 判定して`closeLocalSource(_:)`/`closeRemoteSource(_:)`に振り分けるだけの薄いラッパー
    /// (サイドバー側は`LocalSource`/`RemoteSource`の区別を知らなくてよいようにするため)。
    private func unloadSource(id: String) {
        if let source = localSources.first(where: { $0.id == id }) {
            closeLocalSource(source)
        } else if let source = remoteSources.first(where: { $0.id == id }) {
            closeRemoteSource(source)
        }
    }

    /// 登録済みリンクを選ぶ/新規登録/起動時の自動復元の3箇所から呼ばれる。表示名は
    /// OneDrive/YouTube側のフォルダ名・プレイリスト名ではなくユーザーが付けた`name`を使う
    /// (選ぶ手がかりはこちらのため)。既に同じURLを開いていれば再読み込み(更新)、
    /// 無ければ新規追加する(`RemoteSource.id` = URL文字列で重複判定)。
    /// 既存の他のソースには影響しない。`kind`でOneDriveの`OneDriveShareClient`と
    /// YouTubeの`YouTubePlaylistClient`のどちらでスキャンするかを分岐する。
    /// `name`が空文字なら(YouTubeの新規登録、2026-08-05〜 ― 「名前は自動取得してほしい」
    /// という要望への対応)、取得結果の`sourceName`(プレイリストのタイトル、無ければ1本目の
    /// 動画タイトル)を名前として使う。`registerBookmarkOnSuccess`が`true`の場合、取得成功後に
    /// その自動取得した名前でブックマークを新規登録する(名前が確定する前にブックマークを
    /// 保存できないため、成功を待ってから`addYouTubeBookmarkAndLoad`側の登録処理をここに
    /// 差し込む形にしている)。
    private func openRemote(name: String, shareURL: String, kind: RemoteKind, registerBookmarkOnSuccess: Bool = false, onComplete: (() -> Void)? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = shareURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        // 名前が未確定(自動取得待ち)の間は、サイドバー/トップバーに何も表示できないと
        // 不自然なので、確定するまでURLをそのままプレースホルダーとして表示する。
        let placeholderName = trimmedName.isEmpty ? trimmedURL : trimmedName
        if let index = remoteSources.firstIndex(where: { $0.id == trimmedURL }) {
            remoteSources[index].isLoading = true
            remoteSources[index].errorMessage = nil
            if !trimmedName.isEmpty { remoteSources[index].name = trimmedName }
        } else {
            remoteSources.append(RemoteSource(id: trimmedURL, name: placeholderName, shareURL: trimmedURL, kind: kind, isLoading: true))
        }
        selectedNode = nil
        showsShareLinkSheet = false
        showsYouTubeSheet = false
        persistOpenSources()

        Task {
            do {
                let result: (sourceName: String, videos: [VideoItem])
                switch kind {
                case .oneDrive:
                    result = try await OneDriveShareClient.scan(shareURL: trimmedURL)
                case .youtube:
                    result = try await YouTubePlaylistClient.fetchPlaylist(url: trimmedURL)
                }
                await MainActor.run {
                    guard let index = remoteSources.firstIndex(where: { $0.id == trimmedURL }) else { return }
                    let resolvedName = trimmedName.isEmpty ? result.sourceName : trimmedName
                    // チャンネル名にリンクの登録名を付けておく ― ローカルの同名サブフォルダや
                    // 他の共有リンク/プレイリストとの混同を避け、どのリンク由来か分かるように
                    // する。YouTubeはフォルダ階層を持たないフラットな一覧のため、OneDriveの
                    // ような「登録名 / サブフォルダ名」ではなく登録名だけをそのまま使う。
                    // 共有フォルダの直下(サブフォルダ無し)の動画は`video.channel`が
                    // `VideoScanner.rootChannelLabel`(「(ルート)」)になるが、これを付けても
                    // 情報が増えないため、その場合は登録名だけにする(2026-08-05、
                    // 「チャンネルの 映画 / (ルート) の ルートの部分はいらない」という
                    // 要望に対応)。
                    remoteSources[index].name = resolvedName
                    remoteSources[index].videos = result.videos.map { video in
                        VideoItem(
                            url: video.url,
                            title: video.title,
                            channel: kind == .oneDrive && video.channel != VideoScanner.rootChannelLabel
                                ? "\(resolvedName) / \(video.channel)" : resolvedName,
                            modifiedDate: video.modifiedDate,
                            fileExtension: video.fileExtension,
                            folderPath: video.folderPath,
                            remoteID: video.remoteID,
                            remoteKind: video.remoteKind,
                            thumbnailURL: video.thumbnailURL,
                            knownDurationSeconds: video.knownDurationSeconds
                        )
                    }
                    remoteSources[index].isLoading = false
                    DownloadStore.shared.primeStates(for: remoteSources[index].videos)
                    if registerBookmarkOnSuccess {
                        let bookmark = SharedLinkBookmark(name: resolvedName, url: trimmedURL)
                        youtubePlaylistBookmarks.append(bookmark)
                        Settings.youtubePlaylistBookmarks = youtubePlaylistBookmarks
                    }
                    // 名前が自動取得で確定した場合、開いているソース一覧の永続化(プレースホルダー
                    // 名で仮保存済み)を確定した名前で上書きする。
                    if trimmedName.isEmpty { persistOpenSources() }
                    ensureDurationsLoaded()
                    onComplete?()
                }
            } catch {
                await MainActor.run {
                    guard let index = remoteSources.firstIndex(where: { $0.id == trimmedURL }) else { return }
                    remoteSources[index].isLoading = false
                    remoteSources[index].errorMessage = error.localizedDescription
                    // 起動時の自動復元(`restoreOpenSources`)ではシートは閉じたままなので、
                    // 失敗理由が見える場所を確保するためシートを開く(手動での読み込み失敗時は
                    // 既にシートが開いているため実質no-op)。
                    switch kind {
                    case .oneDrive:
                        shareLoadError = error.localizedDescription
                        showsShareLinkSheet = true
                    case .youtube:
                        youtubeLoadError = error.localizedDescription
                        showsYouTubeSheet = true
                    }
                }
            }
        }
    }

    /// `PlayerPaneView`の再生失敗ポップアップ「再読み込み」ボタンから呼ばれる(2026-08-07追加、
    /// 「通知してそのあと、どのように更新すればいい?」という質問への回答)。OneDriveの
    /// 署名付きURL(`@content.downloadUrl`)は1時間程度で失効するため、再生失敗の多くは
    /// リンク切れが原因 ― `video.remoteID`(再スキャンしても変わらない安定ID、`Models.swift`
    /// 参照)から元の`RemoteSource`を逆引きし、`openRemote`と同じ「既に開いているリンクを
    /// 再度開く=再スキャン」の経路で新しい署名付きURLを取得する。完了後、同じ`remoteID`を持つ
    /// 更新後の`VideoItem`(新しいURL)で`selectedVideo`を差し替え、`PlayerPaneView`側の
    /// `onChange(of: video)`が自動的に新しいURLで再生を再開する。YouTube動画は対象外
    /// (再生失敗の原因が期限切れではなくダウンロード失敗のため、再スキャンでは直らない)。
    private func retryPlayback(for video: VideoItem) {
        guard let remoteID = video.remoteID, video.remoteKind == .oneDrive,
              let source = remoteSources.first(where: { $0.kind == .oneDrive && $0.videos.contains(where: { $0.remoteID == remoteID }) })
        else { return }
        openRemote(name: source.name, shareURL: source.shareURL, kind: .oneDrive) {
            if let refreshed = remoteSources.first(where: { $0.id == source.id })?.videos.first(where: { $0.remoteID == remoteID }) {
                selectedVideo = refreshed
            }
        }
    }

    private func closeRemoteSource(_ source: RemoteSource) {
        remoteSources.removeAll { $0.id == source.id }
        if selectedNode?.sourceID == source.id { selectedNode = nil }
        persistOpenSources()
    }

    /// 現在開いている全ソースをまるごと書き戻す(単純な配列なのでdiffは取らない)。
    private func persistOpenSources() {
        Settings.openLocalFolders = localSources.map(\.url.path)
        Settings.openRemoteLinks = remoteSources.filter { $0.kind == .oneDrive }
            .map { SharedLinkBookmark(name: $0.name, url: $0.shareURL) }
        Settings.openYouTubePlaylists = remoteSources.filter { $0.kind == .youtube }
            .map { SharedLinkBookmark(name: $0.name, url: $0.shareURL) }
    }

    private func addOneDriveBookmarkAndLoad(name: String, url: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
        let bookmark = SharedLinkBookmark(name: trimmedName, url: trimmedURL)
        sharedLinkBookmarks.append(bookmark)
        Settings.sharedLinkBookmarks = sharedLinkBookmarks
        openRemote(name: bookmark.name, shareURL: bookmark.url, kind: .oneDrive)
    }

    private func deleteOneDriveBookmark(_ bookmark: SharedLinkBookmark) {
        sharedLinkBookmarks.removeAll { $0.id == bookmark.id }
        Settings.sharedLinkBookmarks = sharedLinkBookmarks
    }

    /// YouTubeの登録フォームは名前欄を出さない(`OpenRemoteLinkSheet(showsNameField: false)`)
    /// ため`name`は常に空文字で渡ってくる。プレイリストのタイトルを`openRemote`が自動取得する
    /// まで登録できないため、ここでは`SharedLinkBookmark`をまだ作らず
    /// `registerBookmarkOnSuccess: true`で委譲する(`openRemote`のドキュメント参照)。
    private func addYouTubeBookmarkAndLoad(name: String, url: String) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        openRemote(name: "", shareURL: trimmedURL, kind: .youtube, registerBookmarkOnSuccess: true)
    }

    private func deleteYouTubeBookmark(_ bookmark: SharedLinkBookmark) {
        youtubePlaylistBookmarks.removeAll { $0.id == bookmark.id }
        Settings.youtubePlaylistBookmarks = youtubePlaylistBookmarks
    }

    /// 長さフィルターが有効な間、まだ長さが分かっていない動画の長さをバックグラウンドで先読みする。
    /// サムネイル画像は生成しない(`ThumbnailStore.loadDuration`)ため、大量の動画があっても
    /// 画像デコードほどの負荷はかからないが、`limiter` はサムネイル生成と共有しているので
    /// 同時実行数は変わらず抑えられる。
    private func ensureDurationsLoaded() {
        guard isLengthFilterActive else { return }
        let missing = allVideos.filter { videoDurations[$0.url] == nil }
        guard !missing.isEmpty else { return }
        isMeasuringDurations = true
        Task.detached(priority: .utility) {
            await withTaskGroup(of: (URL, TimeInterval?).self) { group in
                for video in missing {
                    group.addTask {
                        (video.url, await ThumbnailStore.shared.loadDuration(for: video))
                    }
                }
                for await (url, duration) in group {
                    guard let duration else { continue }
                    await MainActor.run {
                        self.videoDurations[url] = duration
                    }
                }
            }
            await MainActor.run {
                self.isMeasuringDurations = false
            }
        }
    }
}

/// ミニプレーヤーモードの「常に最前面表示」を実現するためのNSWindowブリッジ
/// (2026-08-07追加)。SwiftUIの`WindowGroup`にはウィンドウレベル・collectionBehaviorを
/// 直接指定するAPIが無いため、`.background`に不可視の`NSView`を仕込んで`view.window`から
/// 実際の`NSWindow`を取得し、AppKit側のプロパティを直接書き換える(`NativeVideoPlayerView`が
/// AVKitを直接ブリッジしているのと同じ「SwiftUIに無い機能はAppKitへ薄く橋渡しする」方針)。
/// ミニプレーヤーへ入った瞬間、`Coordinator.savedFrame`に元のウィンドウフレームを退避してから
/// `level`(`.floating`/`.normal`)・`collectionBehavior`(`.canJoinAllSpaces`/
/// `.fullScreenAuxiliary`を足す ― 他のSpace・フルスクリーン中の別アプリの上にも表示したい
/// ため)を切り替え、画面右下へ寄せる(2026-08-07、「ボリューム(デスクトップの外部ドライブ等の
/// アイコン、右上に出る)と被ってる」という報告への対応 ― 元の位置のまま縮むと画面上部にあった
/// 場合デスクトップのボリュームアイコンと重なっていた)。ミニプレーヤーを終了する際は
/// `savedFrame`へ明示的に`setFrame`で復元する(2026-08-07、「戻るときのサイズはミニプレーヤー
/// 前のサイズ」という要望への対応 ― `.windowResizability(.contentSize)`に任せるだけだと、
/// 通常モードの`ContentView`は`.frame(maxWidth: .infinity, maxHeight: .infinity)`で
/// 「使える分だけ広げたい」という以上の具体的な ideal サイズを持たず、縮んだウィンドウが
/// 元の大きさまで戻る保証がないため、代わりに退避しておいた実測フレームをそのまま書き戻す)。
/// **`savedFrame`は構造体ではなく`Coordinator`(`NSViewRepresentable`が`updateNSView`を
/// 跨いで保持してくれる参照型)に持たせる** ― `WindowLevelAccessor`自体はSwiftUIが
/// 再描画のたびに作り直す値型のため、struct自身のプロパティでは前回の値を跨いで覚えられない。
/// `window.level`が既に`.floating`/`.normal`ならその状態への遷移中ではない(同じモード中に
/// 他の状態変化で`updateNSView`が再度呼ばれただけ)と判断して再配置・再保存しない ― そうしないと
/// ユーザーがミニウィンドウを手動でドラッグして動かしても次の再描画で引き戻されてしまう。
/// `.windowResizability(.contentSize)`によるサイズ追従がこのAppKit呼び出しと非同期に
/// 効いてくる(反映のタイミングがSwiftUI側に委ねられている)ため、`apply`直後の
/// `window.frame`はまだ縮む前のサイズのことがある ― 右下寄せは短い遅延を挟んでから行うことで、
/// 縮んだ後のサイズを基準にできるようにしている。同じ理由で、通常モードへ戻る際の`setFrame`
/// による復元も遅延させている(下記`apply`内のコメント参照 ― 即座に呼ぶと、通常モードに
/// 戻った直後のSwiftUIツリーに対して`.windowResizability(.contentSize)`が独自に行おうとする
/// リサイズに上書きされ、元より低い高さに縮んでしまう不具合が実機で確認された)。
///
/// **`window.contentAspectRatio`(16:9固定)は使わない**(2026-08-07、2つの実機不具合を
/// 踏まえて撤去した ― 導入時は「ドラッグ中に一瞬黒帯が見えるのを防ぎたい」という見た目の
/// 理由だった)。①ミニプレーヤー中は`contentAspectRatio`と`miniPlayerBody`の
/// `.frame(minWidth: 240, maxWidth: 960)`(`.windowResizability(.contentSize)`経由で
/// ウィンドウの最小/最大サイズにもなる)が同時に効いている状態で、標準のzoom(緑ボタン/
/// タイトルバーのダブルクリック)を行うとAppKit純正の`-[NSWindow _zoomToScreen:
/// isMoveToiPad:]`(画面いっぱいへズームするアニメーション)がこれらの制約と衝突し、
/// `-[NSWindow _adjustNeedsDisplayRegionForNewFrame:]`内でクラッシュすることが実機の
/// クラッシュレポート(EXC_BREAKPOINT/SIGTRAP、macOS 26.5.2)で確認された。②通常モードに
/// 戻る際`.zero`を設定してもAppKit側で完全には解除されず、戻った後に手動でウィンドウ端を
/// ドラッグしてリサイズしようとすると16:9維持が働き続けて高さが縮む不具合も確認された。
/// 見た目の16:9維持は`miniPlayerBody`側の`.aspectRatio(16/9, contentMode: .fit)`
/// (SwiftUI側)だけに任せることにした ― ドラッグ中にSwiftUIの再計算が追いつくまでのごく
/// 一瞬だけ見た目がずれる可能性はあるが、クラッシュ・リサイズ不能という実害の方が大きいため
/// この妥協を選んだ。
///
/// **ネイティブzoom自体は`NSWindowDelegate.windowShouldZoom(_:toFrame:)`で止める**
/// (2026-08-07、「緑のボタンを押すとクラッシュします」→さらに「タイトルバーのダブル
/// クリックでもクラッシュする」という2件のクラッシュレポートへの対応)。当初は緑ボタンの
/// `NSButton.target`/`.action`を乗っ取る方式だったが、タイトルバーのダブルクリックによる
/// zoom(`-[NSTitledFrame _handlePossibleDoubleClickForEvent:onlyZoomInDragRegion:]`)は
/// ボタンを経由せず直接`_zoomToScreen:`を呼ぶため、ボタン側の乗っ取りだけでは防げないことが
/// 2件目のクラッシュで判明した。`windowShouldZoom(_:toFrame:)`はzoomのトリガー経路(ボタン
/// クリック・タイトルバーのダブルクリックのどちらでも)AppKitが実際にリサイズする**前**に
/// 必ず呼ぶ公式の関門のため、ここで`false`を返せばトリガー経路によらずクラッシュする
/// ネイティブzoomアニメーション自体を確実に止められる。ミニプレーヤー中に`false`を返す
/// ついでに`onZoomButtonClicked`(＝ミニプレーヤー解除)を呼ぶことで、「zoomしようとしたら
/// ミニプレーヤーを解除する」という動作も実現している。**`window.delegate`は他に何か
/// (SwiftUIの内部実装など)が既に使っている可能性があるため、奪うのではなく
/// `Coordinator`を割り込ませて他のメソッドは元の`delegate`へ`forwardingTarget(for:)`で
/// 転送する**(`responds(to:)`/`forwardingTarget(for:)`はObjective-Cのメッセージ転送の
/// 仕組みで、`NSObject`を継承していれば`Coordinator`でもオーバーライドできる)。
/// `window.delegate !== coordinator`のときだけ(何か他のものが割り込んで上書きしていた
/// 場合の保険も兼ねて)現在の`delegate`を`previousDelegate`に退避してから差し替える ―
/// 一度差し替えた後の`apply`呼び出しでは`window.delegate === coordinator`なので
/// 再取得・再差し替えはしない。
private struct WindowLevelAccessor: NSViewRepresentable {
    let isFloatingOnTop: Bool
    /// ミニプレーヤー中にネイティブzoom(緑ボタン/タイトルバーのダブルクリック)が
    /// 試みられたときに呼ばれる(2026-08-07追加、上記`Coordinator.windowShouldZoom`の
    /// ドキュメント参照)。`ContentView`は`{ isMiniPlayerMode = false }`を渡す ― 動画右上の
    /// 拡大アイコンのボタンと同じ効果。
    let onZoomButtonClicked: () -> Void

    final class Coordinator: NSObject, NSWindowDelegate {
        var savedFrame: NSRect?
        var isMiniModeActive = false
        var onZoomAttempt: (() -> Void)?
        weak var previousDelegate: NSWindowDelegate?

        func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
            guard isMiniModeActive else {
                return previousDelegate?.windowShouldZoom?(window, toFrame: newFrame) ?? true
            }
            onZoomAttempt?()
            return false
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if aSelector == #selector(NSWindowDelegate.windowShouldZoom(_:toFrame:)) {
                return true
            }
            return previousDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if aSelector == #selector(NSWindowDelegate.windowShouldZoom(_:toFrame:)) {
                return nil
            }
            return previousDelegate
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window, coordinator: context.coordinator) }
    }

    private func apply(to window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        coordinator.onZoomAttempt = onZoomButtonClicked
        coordinator.isMiniModeActive = isFloatingOnTop
        if window.delegate !== coordinator {
            coordinator.previousDelegate = window.delegate
            window.delegate = coordinator
        }

        if isFloatingOnTop {
            let isEnteringMiniMode = window.level != .floating
            if isEnteringMiniMode {
                coordinator.savedFrame = window.frame
            }
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            if isEnteringMiniMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    positionAtBottomRight(window)
                }
            }
        } else {
            let wasFloating = window.level == .floating
            window.level = .normal
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            if wasFloating, let savedFrame = coordinator.savedFrame {
                coordinator.savedFrame = nil
                // `.windowResizability(.contentSize)`が、通常モードに戻った直後の
                // SwiftUIツリー(`.frame(maxWidth: .infinity, maxHeight: .infinity)`に
                // 戻った直後の再計算)に合わせてウィンドウを独自に(小さく)リサイズしようと
                // 競合することがある(`positionAtBottomRight`と同じ理由で遅延させている)。
                // ここで即座に`setFrame`すると、その直後にSwiftUI側の自動リサイズに
                // 上書きされて元のサイズより低い高さに縮んでしまう不具合が実機で確認された
                // ため、短い遅延を挟んでSwiftUI側の再計算を先に終わらせてから最後に
                // 退避しておいたフレームで上書きする。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    window.setFrame(savedFrame, display: true, animate: true)
                }
            }
        }
    }

    private func positionAtBottomRight(_ window: NSWindow) {
        guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let margin: CGFloat = 20
        let origin = NSPoint(
            x: screenFrame.maxX - window.frame.width - margin,
            y: screenFrame.minY + margin
        )
        window.setFrameOrigin(origin)
    }
}
