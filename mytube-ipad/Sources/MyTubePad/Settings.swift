import Foundation

/// UserDefaults キーの一元管理(mytube Mac版のCore/Settings.swiftと同じ方針)。
enum Settings {
    private static let sharedLinkBookmarksKey = "mytubepad.sharedLinkBookmarks"
    private static let homeViewModeKey = "mytubepad.homeViewMode"
    private static let downloadedVideoInfosKey = "mytubepad.downloadedVideoInfos"

    /// 登録済みのOneDrive共有リンク(名前+URL)一覧。
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

    /// `SourceGridView`の表示形式(グリッド/リスト、2026-08-27追加)。
    static var homeViewMode: HomeViewMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: homeViewModeKey) else { return .grid }
            return HomeViewMode(rawValue: raw) ?? .grid
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: homeViewModeKey) }
    }

    /// ダウンロード済み動画のメタデータ(キーは`VideoItem.remoteID`、2026-08-27追加)。
    /// `DownloadStore`が読み書きする ― `Views/LocalDownloadsView.swift`参照。
    static var downloadedVideoInfos: [String: DownloadedVideoInfo] {
        get {
            guard let data = UserDefaults.standard.data(forKey: downloadedVideoInfosKey) else { return [:] }
            return (try? JSONDecoder().decode([String: DownloadedVideoInfo].self, from: data)) ?? [:]
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: downloadedVideoInfosKey)
        }
    }
}
