import Foundation

/// UserDefaults キーの一元管理。
enum Settings {
    private static let openLocalFoldersKey = "mytube.openLocalFolders"
    private static let openRemoteLinksKey = "mytube.openRemoteLinks"
    private static let sharedLinkBookmarksKey = "mytube.sharedLinkBookmarks"
    private static let openYouTubePlaylistsKey = "mytube.openYouTubePlaylists"
    private static let youtubePlaylistBookmarksKey = "mytube.youtubePlaylistBookmarks"
    private static let homeViewModeKey = "mytube.homeViewMode"
    private static let autoplayEnabledKey = "mytube.autoplayEnabled"
    private static let maxCacheBytesKey = "mytube.maxCacheBytes"
    private static let favoriteKeysKey = "mytube.favoriteKeys"
    private static let recentlyPlayedKeysKey = "mytube.recentlyPlayedKeys"
    private static let manualEpisodeTagsKey = "mytube.manualEpisodeTags"

    /// 現在開いているローカルフォルダのパス一覧(複数可)。非サンドボックスアプリのため
    /// 素のパス文字列で十分(security-scoped bookmark は不要 — myorganizer 等の他アプリと同じ方針)。
    /// `ContentView`が開く/閉じるたびに全件書き戻す(単純な配列なのでdiffは取らない)。
    static var openLocalFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: openLocalFoldersKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: openLocalFoldersKey) }
    }

    /// 現在開いているOneDrive共有リンク(名前+URL)一覧(複数可)。`sharedLinkBookmarks`
    /// (下記、ユーザーが後で選べるよう保存した一覧)とは別物 ― こちらは「今まさに開いている
    /// もの」の一覧で、閉じれば消える。型は`SharedLinkBookmark`を流用しているが、
    /// `id`はここでは意味を持たない(保存のたびに作り直され、復元時は`name`/`url`だけ使う)。
    static var openRemoteLinks: [SharedLinkBookmark] {
        get {
            guard let data = UserDefaults.standard.data(forKey: openRemoteLinksKey) else { return [] }
            return (try? JSONDecoder().decode([SharedLinkBookmark].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: openRemoteLinksKey)
        }
    }

    /// 登録済みのOneDrive共有リンク(名前+URL)一覧。件数も少なく構造も単純なため、
    /// renamerのpresets.jsonのような専用ファイルではなくUserDefaultsにJSONとして保存する。
    static var sharedLinkBookmarks: [SharedLinkBookmark] {
        get {
            guard let data = UserDefaults.standard.data(forKey: sharedLinkBookmarksKey) else { return [] }
            return (try? JSONDecoder().decode([SharedLinkBookmark].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: sharedLinkBookmarksKey)
        }
    }

    /// 現在開いているYouTubeプレイリスト(名前+URL)一覧(複数可)。`openRemoteLinks`の
    /// YouTube版 ― OneDriveと完全に別のキー/配列にしているのは、`SharedLinkBookmark`に
    /// 種別フィールドを追加して後方互換のデコード処理を書くより、素直にキーを分けた方が
    /// 単純だったため。
    static var openYouTubePlaylists: [SharedLinkBookmark] {
        get {
            guard let data = UserDefaults.standard.data(forKey: openYouTubePlaylistsKey) else { return [] }
            return (try? JSONDecoder().decode([SharedLinkBookmark].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: openYouTubePlaylistsKey)
        }
    }

    /// 登録済みのYouTubeプレイリストURL(名前+URL)一覧。`sharedLinkBookmarks`のYouTube版。
    static var youtubePlaylistBookmarks: [SharedLinkBookmark] {
        get {
            guard let data = UserDefaults.standard.data(forKey: youtubePlaylistBookmarksKey) else { return [] }
            return (try? JSONDecoder().decode([SharedLinkBookmark].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: youtubePlaylistBookmarksKey)
        }
    }

    /// ホーム画面の表示形式(グリッド/ハイブリッド)。既定は`.grid`(従来からの見た目)。
    static var homeViewMode: HomeViewMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: homeViewModeKey) else { return .grid }
            return HomeViewMode(rawValue: raw) ?? .grid
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: homeViewModeKey) }
    }

    /// 視聴画面の「自動再生」トグル(2026-08-05追加)。オンなら最後まで再生した動画の次に
    /// 「次の動画」欄の次の項目を自動的に再生する(従来からの既定挙動)。既定値`true`にするため
    /// `bool(forKey:)`(未設定時に`false`を返す)ではなく`object(forKey:)`で未設定を判定する。
    static var autoplayEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: autoplayEnabledKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoplayEnabledKey) }
    }

    /// `Core/DownloadStore.swift`のダウンロード済みキャッシュ(`~/Library/Application
    /// Support/MyTube/downloads/`)の上限バイト数(2026-08-05追加、「ローカルキャッシュの
    /// 最大値を設定したい。Defaultは5G」という要望への対応)。既定は5GB(10進、`ByteCountFormatter`
    /// の`.file`スタイル表示と揃える)。超過時は`DownloadStore.enforceCacheLimit()`が
    /// 更新日時の古いファイルから順に削除する。
    static var maxCacheBytes: Int64 {
        get { (UserDefaults.standard.object(forKey: maxCacheBytesKey) as? Int64) ?? 5_000_000_000 }
        set { UserDefaults.standard.set(newValue, forKey: maxCacheBytesKey) }
    }

    /// お気に入りに登録した動画の`VideoItem.stableKey`の集合(2026-08-14追加、
    /// 「お気に入りチャンネルを追加してほしい。リスト時や動画再生時に登録可能に」という
    /// 要望への対応)。`Core/FavoritesStore.swift`が唯一の読み書き元。
    static var favoriteKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: favoriteKeysKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: favoriteKeysKey) }
    }

    /// 最近再生した動画の`VideoItem.stableKey`一覧、新しい順(2026-08-14追加)。
    /// `Core/RecentlyPlayedStore.swift`が唯一の読み書き元。
    static var recentlyPlayedKeys: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentlyPlayedKeysKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentlyPlayedKeysKey) }
    }

    /// 動画ごとに手動で追加したタグ(`VideoItem.stableKey` → タグ名の集合、2026-08-22追加、
    /// 「手動で既存または新規のタグをエピソードに追加できる?」という要望への対応)。
    /// `Core/EpisodeTagStore.swift`が唯一の読み書き元。`ConanEpisodeTags`の自動判定
    /// (タイトルのキーワードだけで決まる、保存の必要が無い)とは別に、これはユーザーが
    /// 明示的に足した分だけを持つ。
    static var manualEpisodeTags: [String: Set<String>] {
        get {
            guard let data = UserDefaults.standard.data(forKey: manualEpisodeTagsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Set<String>].self, from: data)) ?? [:]
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: manualEpisodeTagsKey)
        }
    }
}
