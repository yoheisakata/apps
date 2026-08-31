import SwiftUI

struct ContentView: View {
    /// 常に登録済みにする共有リンク(2026-08-27追加、ユーザーからの明示的な要望 ― 毎回
    /// 「+」から手でURLを貼り付けなくても、起動すれば最初からリストにあるようにする)。
    /// URLの一致で判定するため、ユーザーが手動で削除しても次回起動時に復活する
    /// (「ハードコード」の意図通り、常に存在する既定エントリとして扱う)。
    private static let hardcodedBookmarks: [(name: String, url: String)] = [
        (name: "コナン", url: "https://1drv.ms/f/c/22558ab42b6166a7/IgCnZmErtIpVIIAisXgGAAAAAePdAtiUUOTbuvD5eW1HrjM?e=7PLUIH"),
        (name: "映画", url: "https://1drv.ms/f/c/6b83b2b7da86a08f/IgCPoIbat7KDIIBrBBEAAAAAAeirLHjJlkcimv4OevKejxA?e=Z2I0vf"),
        (name: "アニメ", url: "https://1drv.ms/f/c/22558ab42b6166a7/IgCnZmErtIpVIIAiXAEAAAAAAR9-Rj8uJiqW61VBu8ZMCto?e=vmrYWU"),
        (name: "ドラマ", url: "https://1drv.ms/f/c/22558ab42b6166a7/IgBnnolVejw3QpwuiiuYskleAUVk1jhTKS9G_zEtwKM_xNM?e=6USt5k"),
    ]

    @State private var bookmarks: [SharedLinkBookmark] = Self.loadBookmarksEnsuringDefaults()
    /// キーは`SharedLinkBookmark.id.uuidString`。選択・スキャンのたびに埋まる実行時状態。
    @State private var sources: [String: RemoteSource] = [:]
    @State private var selectedBookmarkID: SharedLinkBookmark.ID?
    /// 「保存済み」一覧の選択状態(2026-08-27追加、「ローカルに保存した動画の一覧もほしい」
    /// という要望への対応。表示名は当初「ローカル保存済み」だったが、2026-08-28に
    /// 「『ローカル』という表示はいらない」という要望を受けて「保存済み」に短縮した ―
    /// この`@State`名自体は変えていない)。`selectedBookmarkID`とは排他 ― どちらかを
    /// 選んだらもう片方を`nil`/`false`に戻す(下記`body`の各アクション参照)。
    /// `SharedLinkBookmark.ID`(UUID)の集合に紛れ込ませず別の`@State`にしているのは、
    /// `List(selection:)`のタグ型を汚さずに済むため。
    @State private var isLocalDownloadsSelected = false
    @State private var showingAddSheet = false
    @State private var playingVideo: VideoItem?
    /// `playingVideo`を再生し終えたら自動的に次へ進むためのキュー(2026-08-27追加、
    /// 「次の動画に自動で進むようにしてほしい」という要望への対応)。`SourceGridView`が
    /// タップされた時点で表示していた一覧(フォルダタブ・タグフィルター適用後)をそのまま渡す。
    @State private var playingQueue: [VideoItem] = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedBookmarkID) {
                // 「保存済み」は共有リンクではないため`List(selection:)`の
                // `SharedLinkBookmark.ID`タグ体系には乗せず、選択したら`selectedBookmarkID`を
                // 明示的に`nil`へ戻すただの`Button`にしている(2026-08-27追加)。
                // 一時的にアイコンのみ表示にしたが(2026-08-28、「アイコンだけでOK」)、
                // 同日中に「アイコンじゃなくて、保存済みという表示に変えて」と撤回されたため
                // テキスト表示に戻した。
                Button {
                    selectedBookmarkID = nil
                    isLocalDownloadsSelected = true
                } label: {
                    Text("保存済み")
                        .font(.caption)
                }
                .listRowBackground(isLocalDownloadsSelected ? Color.accentColor.opacity(0.18) : Color.clear)

                ForEach(bookmarks) { bookmark in
                    Text(bookmark.name)
                        .font(.caption)
                        .tag(bookmark.id)
                }
                .onDelete(perform: deleteBookmarks)
            }
            .navigationTitle("MyTube Pad")
            // サイドバーを狭く・文字も小さくする(2026-08-27追加、「左バーを狭くしたい。
            // 文字も小さくして」という要望に対応した後、「もうすこしつめてほしい」で
            // 2段階目の縮小をした)。**2026-08-28、「固定サイズにして、長くて全角4文字
            // 入ればOK」という要望を受け、可変幅(min/ideal/max)から単一値の固定幅に
            // 変更した** ― ユーザーがドラッグでリサイズできる可変幅ではなく、常にこの
            // 幅で固定される(`navigationSplitViewColumnWidth(_:)`の単一値オーバーロードは
            // min=ideal=maxを同じ値に設定するのと同じ)。
            .navigationSplitViewColumnWidth(130)
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if bookmarks.isEmpty {
                    ContentUnavailableView(
                        "リンクがありません",
                        systemImage: "link",
                        description: Text("右上の+からOneDriveの共有リンクを登録してください")
                    )
                }
            }
        } detail: {
            if isLocalDownloadsSelected {
                LocalDownloadsView(onPlay: { video, queue in
                    playingQueue = queue
                    playingVideo = video
                })
            } else if let bookmark = bookmarks.first(where: { $0.id == selectedBookmarkID }) {
                SourceGridView(
                    bookmark: bookmark,
                    source: sources[bookmark.id.uuidString],
                    onLoad: { await loadSource(bookmark: bookmark) },
                    onPlay: { video, queue in
                        playingQueue = queue
                        playingVideo = video
                    }
                )
                .id(bookmark.id)
            } else {
                ContentUnavailableView(
                    "リンクを選んでください",
                    systemImage: "sidebar.left",
                    description: Text("左のリストからOneDriveの共有リンクを選ぶと動画一覧が表示されます")
                )
            }
        }
        .onChange(of: selectedBookmarkID) { _, newValue in
            // 共有リンクを選んだら「保存済み」の選択は解除する(2026-08-27追加、
            // 上記`isLocalDownloadsSelected`のドキュメント参照 ― 逆方向(「保存済み」を
            // 選んだら`selectedBookmarkID`を`nil`に戻す)はボタンのアクション内で
            // 直接行っている)。
            if newValue != nil { isLocalDownloadsSelected = false }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddLinkSheet { name, url in
                addBookmark(name: name, url: url)
            }
        }
        .fullScreenCover(item: $playingVideo) { video in
            PlayerView(video: video, queue: playingQueue) { playingVideo = nil }
        }
    }

    private func addBookmark(name: String, url: String) {
        let bookmark = SharedLinkBookmark(name: name, url: url)
        bookmarks.append(bookmark)
        Settings.sharedLinkBookmarks = bookmarks
        selectedBookmarkID = bookmark.id
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        let removed = offsets.map { bookmarks[$0] }
        bookmarks.remove(atOffsets: offsets)
        Settings.sharedLinkBookmarks = bookmarks
        for bookmark in removed {
            sources.removeValue(forKey: bookmark.id.uuidString)
            if selectedBookmarkID == bookmark.id {
                selectedBookmarkID = nil
            }
        }
    }

    private static func loadBookmarksEnsuringDefaults() -> [SharedLinkBookmark] {
        var bookmarks = Settings.sharedLinkBookmarks
        var didChange = false
        for hardcoded in hardcodedBookmarks where !bookmarks.contains(where: { $0.url == hardcoded.url }) {
            bookmarks.append(SharedLinkBookmark(name: hardcoded.name, url: hardcoded.url))
            didChange = true
        }
        if didChange {
            Settings.sharedLinkBookmarks = bookmarks
        }
        return bookmarks
    }

    private func loadSource(bookmark: SharedLinkBookmark) async {
        let key = bookmark.id.uuidString
        // キャンセルされたときに「まっさらな未読み込み状態に戻してよいか」の判定に使う
        // (2026-08-28追加、下記catch節参照)。この時点(スキャン開始前)で既に動画が
        // 表示できていたかどうかを覚えておく。
        let hadExistingVideos = !(sources[key]?.videos.isEmpty ?? true)
        if sources[key] == nil {
            // キャッシュがあれば即座にそれを表示しつつ、下の`scanWithRetry`をバックグラウンドで
            // 走らせて最新の結果に差し替える(2026-08-28追加、「毎回OneDriveから一覧を
            // とってくるのを効率よくできないか」という要望への対応。`RemoteListCache`参照 ―
            // 新規にこのリンクを開く場合(`sources[key] == nil`)だけの経路で、既に開いている
            // リンクの再スキャン(🔄相当、プルダウン更新)ではキャッシュを読み直さない)。
            if let cached = RemoteListCache.load(for: bookmark.url) {
                sources[key] = RemoteSource(name: cached.sourceName, shareURL: bookmark.url, videos: cached.videos)
            } else {
                sources[key] = RemoteSource(name: bookmark.name, shareURL: bookmark.url)
            }
        }
        sources[key]?.isLoading = true
        sources[key]?.errorMessage = nil
        do {
            let result = try await Self.scanWithRetry(shareURL: bookmark.url)
            sources[key]?.videos = result.videos
            sources[key]?.isLoading = false
            RemoteListCache.save(shareURL: bookmark.url, sourceName: result.sourceName, videos: result.videos)
        } catch {
            if Self.isCancellation(error) {
                if hadExistingVideos {
                    // 2026-08-28追加、「プルダウンしたらローディングマークが出て一覧が
                    // 消えた」というバグ報告への対応 ― 既に一覧を表示できていた状態での
                    // プルダウン更新(リフレッシュ)がキャンセルされた場合、以前は下の
                    // `else`節と同じく`sources`からエントリごと取り除いていたため、
                    // せっかく表示できていた一覧までまっさらに消えてしまっていた。
                    // 表示中のデータがある場合はそれを残したまま、ローディング状態だけ
                    // 元に戻す(ユーザーは何も失わない ― 必要なら再度プルダウンすればよい)。
                    sources[key]?.isLoading = false
                } else {
                    // 読み込み中に別のリンクへ切り替える等でこの`Task`がキャンセルされ、
                    // かつまだ何も表示できていなかった場合は「失敗」として`errorMessage`に
                    // 残さない ― `sources`からこのキーごと取り除いて`source == nil`の
                    // 状態に戻すことで、次にこのリンクを選び直したときに
                    // `SourceGridView`の`.task(id: bookmark.id)`が自動的に再読み込み
                    // してくれる(2026-08-27、「ローディングがcancelledになったら
                    // 再ロードできない」というバグ報告への対応。以前はキャンセルも
                    // 他のエラーと同じく`errorMessage`へ格納していたため、`source`が
                    // 「キャンセルされました」を保持したまま非nilで残り、`.task(id:)`の
                    // `if source == nil`ガードにより選び直しても再読み込みされなく
                    // なっていた)。
                    sources.removeValue(forKey: key)
                }
            } else {
                sources[key]?.errorMessage = error.localizedDescription
                sources[key]?.isLoading = false
            }
        }
    }

    /// Swift Taskの協調的キャンセル(`CancellationError`)、および`URLSession`が
    /// キャンセルされたリクエストに対して返す`URLError(.cancelled)`のどちらも
    /// 「キャンセルされた」とみなす。
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// 「The network connection was lost」(`URLError.networkConnectionLost`)・
    /// タイムアウトのような一時的なネットワークエラーだけ自動で1回リトライする
    /// (2026-08-27、「アニメ」共有リンク(サブフォルダの多い大きめのライブラリ)で
    /// 実際に報告されたバグへの対応)。`OneDriveShareClient.scan`はフォルダを再帰的に
    /// 辿るたびにOneDriveの内部APIへ逐次リクエストするため、フォルダ数が多いほど
    /// 途中のどこかで一時的な接続断を踏む確率が上がる ― ユーザーに毎回プルダウンでの
    /// 手動リトライを強いる代わりに、まずここで1回だけ自動再試行する(それでも失敗したら
    /// 通常通り`errorMessage`へ表示し、以降は手動のプルダウン更新に委ねる)。
    private static func scanWithRetry(shareURL: String) async throws -> (sourceName: String, videos: [VideoItem]) {
        do {
            return try await OneDriveShareClient.scan(shareURL: shareURL)
        } catch {
            guard isTransientNetworkError(error) else { throw error }
            return try await OneDriveShareClient.scan(shareURL: shareURL)
        }
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .networkConnectionLost || urlError.code == .timedOut
    }
}
