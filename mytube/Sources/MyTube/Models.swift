import Foundation

/// リモートソースの種類。`VideoItem.remoteKind`/`RemoteSource.kind`で共通して使う
/// (`nil`=ローカル)。サイドバーのグループ分け(`Views/SidebarView.swift`)、
/// `DownloadStore`のダウンロード方式の分岐(OneDriveはHTTP直DL、YouTubeはyt-dlp)、
/// UI文言の出し分けに使う。
enum RemoteKind: Hashable {
    case oneDrive
    case youtube

    var displayName: String {
        switch self {
        case .oneDrive: return "OneDrive"
        case .youtube: return "YouTube"
        }
    }
}

/// フォルダ配下でスキャンして見つかった1本の動画ファイル。
struct VideoItem: Identifiable, Hashable {
    /// ファイルパスをそのまま識別子にする(同じフォルダ内で重複しない)。
    var id: URL { url }

    let url: URL
    /// 拡張子を除いたファイル名。
    let title: String
    /// ルートフォルダ直下のサブフォルダ名(「チャンネル」として扱う)。
    /// ルート直下に置かれた動画は `VideoScanner.rootChannelLabel` になる。
    let channel: String
    let modifiedDate: Date?
    /// 拡張子(ドット無し、小文字)。リモート動画の`url`(`@content.downloadUrl`)は
    /// パス自体が`download.aspx`のような固定文字列で拡張子を含まないため、
    /// `url.pathExtension`に頼れない ― `DownloadStore`がローカル保存時のファイル名に使う。
    let fileExtension: String
    /// ソースのルートから見た、この動画を含むフォルダのパスコンポーネント(ルート直下なら
    /// `[]`)。`channel`(カード/視聴画面の表示ラベル、1階層目のサブフォルダ名だけ)とは別物 ―
    /// サイドバーのネストしたフォルダツリー(`Core/FolderTree.swift`)の構築とフィルタ専用。
    var folderPath: [String] = []
    /// OneDrive共有リンク/YouTubeプレイリスト経由の動画だけ非nil(それぞれのクライアントが
    /// 設定するアイテムID/動画ID)。ローカル動画は常にnil。OneDriveの`url`は
    /// `@content.downloadUrl`由来の署名付きURLで、トークンの再発行のたびにクエリ文字列が
    /// 変わり同一ファイルでも値が変化するため、`ThumbnailStore`のキャッシュキーやサムネイル
    /// 生成の要否判定には使えない ― 代わりにこの安定したIDを使う
    /// (`ThumbnailStore.cacheKey`参照)。また `VideoCardView` はこれが非nilの動画には
    /// 削除操作(ゴミ箱移動)を出さない(共有元のファイルを操作する手段を持たないため)。
    var remoteID: String? = nil
    /// `remoteID`と対になるソース種別。`nil`=ローカル。
    var remoteKind: RemoteKind? = nil
    /// YouTube動画のサムネイル直リンク(`https://i.ytimg.com/vi/<id>/hqdefault.jpg`)。
    /// 非nilなら`ThumbnailStore`はAVAssetでのフレーム抽出(未ダウンロードのYouTube動画では
    /// `url`が再生不可能なwatchページURLのため失敗する)ではなくこちらを直接フェッチする。
    var thumbnailURL: URL? = nil
    /// YouTubeプレイリスト取得時(`YouTubePlaylistClient`)にyt-dlpのメタデータから
    /// 判明済みの長さ。非nilなら`ThumbnailStore`は未ダウンロードの動画をAVAssetで
    /// プロービングせずこの値をそのまま使う。
    var knownDurationSeconds: TimeInterval? = nil

    var isRemote: Bool { remoteID != nil }
}

/// 「共有リンクを開く」/「YouTubeプレイリストを開く」シートに登録する、名前付きのURL。
/// OneDrive共有リンク・YouTubeプレイリストURLの両方に使う共通の形(名前+URLだけの単純な構造で
/// 区別する必要がないため)― どちらの種別かは`Settings`側のキー(`sharedLinkBookmarks`/
/// `youtubePlaylistBookmarks`)で分けて保存する。UserDefaultsにJSONとして永続化する
/// (複数リンクを毎回貼り直さず選ぶだけで開けるようにするため)。
struct SharedLinkBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
}

/// 現在開いている1つのローカルフォルダ(複数同時に開ける、2026-08-04〜)。
/// `id`はパス文字列 ― 同じフォルダを二重に開かないための重複排除キー
/// (`ContentView.openFolder(_:)`参照)。
/// `Equatable`合成(2026-08-06追加、`Views/SidebarView.swift`が`onChange(of: localSources)`で
/// 実際に中身が変わった時だけフォルダツリーを再構築するために必要 ― 全フィールドが
/// `Equatable`/`Hashable`(`VideoItem`は`Hashable`)なので自動合成できる)。
struct LocalSource: Identifiable, Equatable {
    let id: String
    let url: URL
    var videos: [VideoItem] = []
    var isScanning = false

    var name: String { url.lastPathComponent }
}

/// サイドバーのフォルダツリー(`Core/FolderTree.swift`)でどのノードが選択されているかを表す。
/// `sourceID`だけでなく`folderPath`も持つのは、複数ソースを同時に開いた際に同名のサブフォルダが
/// 別ソースにも存在しうるため(`folderPath`だけでは選択対象のソースを一意に特定できない)。
struct SidebarSelection: Hashable {
    let sourceID: String
    /// `[]`ならそのソース全体を選択(祖先が一致する動画は配下も全部含む、explorerと同じ挙動)。
    let folderPath: [String]
}

/// 現在開いている1つのOneDrive共有リンク/YouTubeプレイリスト(複数同時に開ける、2026-08-04〜)。
/// `id`はURL文字列 ― 同じリンクを二重に開かないための重複排除キー
/// (`ContentView.openRemote(name:shareURL:kind:)`参照)。`SharedLinkBookmark`(登録済み
/// リンクの保存用)とは別物 ― こちらは「今まさに読み込み中/読み込み済み」の実行時状態を持つ。
/// `kind`でOneDrive/YouTubeを区別する(サイドバーのグループ分け、`ContentView.openRemote`が
/// どちらのクライアントでスキャンするかの分岐、`DownloadStore`のダウンロード方式の分岐に使う)。
/// `Equatable`合成(2026-08-06追加、`LocalSource`と同じ理由)。
struct RemoteSource: Identifiable, Equatable {
    let id: String
    var name: String
    var shareURL: String
    let kind: RemoteKind
    var videos: [VideoItem] = []
    var isLoading = false
    var errorMessage: String?
}

/// トップバーの並び替え(2026-08-05、「期間のフィルタはいらない。かわりにソート機能を
/// つけて」という要望に対応 ― 以前あった期間フィルター(`TimeFilter`、更新日時で絞り込む)を
/// 廃止し、絞り込みではなく並び替えに置き換えた)。既定は`titleAscending`
/// (`ContentView.filteredVideos`の以前からの固定ソート方式=ファイル名昇順)。
enum SortOption: String, CaseIterable, Identifiable {
    case titleAscending, titleDescending, dateNewest, dateOldest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .titleAscending: return "タイトル (A→Z)"
        case .titleDescending: return "タイトル (Z→A)"
        case .dateNewest: return "更新日時が新しい順"
        case .dateOldest: return "更新日時が古い順"
        }
    }

    /// `ContentView.filteredVideos`が`videos.sorted(by:)`にそのまま渡す比較関数。
    /// 更新日時が無い動画(`modifiedDate == nil` ― OneDrive/YouTubeの一部動画で起こりうる)は
    /// 日時順ソートの末尾に固定する(不明な日時を「一番古い」扱いにしても直感に反しないため)。
    func areInIncreasingOrder(_ lhs: VideoItem, _ rhs: VideoItem) -> Bool {
        switch self {
        case .titleAscending:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case .titleDescending:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedDescending
        case .dateNewest, .dateOldest:
            guard let lhsDate = lhs.modifiedDate else { return false }
            guard let rhsDate = rhs.modifiedDate else { return true }
            return self == .dateNewest ? lhsDate > rhsDate : lhsDate < rhsDate
        }
    }
}

/// ホーム画面の表示形式(2026-08-05追加、「MyTubeの動画の表示の仕方を増やしたい」という
/// 要望への対応)。`TopBarView`のセグメントピッカーで切り替え、`Settings.homeViewMode`に
/// 永続化する。既定は`grid`(従来からの見た目)。当初は`grid`/`list`/`hybrid`の3種類
/// だったが、`list`(サムネイル無し)と`hybrid`(小さいサムネイル付き)がFinder風の表形式に
/// 統一された結果ほぼ同じ見た目になったため、「一覧は削除します」という要望を受けて`list`を
/// 廃止した(永続化済みの`"list"`という値は`Settings.homeViewMode`の`??.grid`
/// フォールバックで安全に`grid`扱いになる)。
enum HomeViewMode: String, CaseIterable, Identifiable {
    /// 従来のサムネイルグリッド。
    case grid
    /// Finderのリスト表示のような表形式(名前・長さ・ソース・チャンネル)+小さいサムネイル。
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "グリッド"
        case .hybrid: return "ハイブリッド"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .hybrid: return "rectangle.grid.1x2"
        }
    }
}
