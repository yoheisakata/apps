import Foundation

/// UserDefaults キーの一元管理(myslideshow-ipad/mygallery Mac版の`Settings.swift`と
/// 同じ方針)。キーは`mygalleryipad.`プレフィックス。
enum Settings {
    private static let photoDurationKey = "mygalleryipad.photoDurationSeconds"
    private static let shuffleEnabledKey = "mygalleryipad.shuffleEnabled"
    private static let timeLimitMinutesKey = "mygalleryipad.timeLimitMinutes"
    private static let folderSelectionsKey = "mygalleryipad.folderSelections"

    /// 写真1枚あたりの表示秒数(スライドショー用)。既定6秒。
    static var photoDurationSeconds: Double {
        get {
            let value = UserDefaults.standard.double(forKey: photoDurationKey)
            return value > 0 ? value : 6.0
        }
        set { UserDefaults.standard.set(newValue, forKey: photoDurationKey) }
    }

    /// スライドショーの順番をシャッフルするか。既定はfalse(フォルダ順)。
    static var shuffleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: shuffleEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: shuffleEnabledKey) }
    }

    /// スライドショーの時間制限(分)。**5分刻み**、`nil`(既定)は無制限。
    static var timeLimitMinutes: Int? {
        get {
            let value = UserDefaults.standard.integer(forKey: timeLimitMinutesKey)
            return value > 0 ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: timeLimitMinutesKey) }
    }

    /// リンクごと(`HardcodedLink.id`がキー)の、年/月フォルダツリーで選んだパスの集合。
    /// パスは`/`区切り文字列にエンコードする(年フォルダ自身は"2026"、月フォルダは
    /// "2026/09")。mygallery(Mac版)の`GallerySettings.folderTreeSelections`と同じ
    /// 発想 ― 「動画/写真タブを開いたら前回選んでいたものを自動で復元する」ため、
    /// キー無しは「全フォルダ表示」を意味する。
    static var folderSelections: [String: Set<String>] {
        get {
            guard let data = UserDefaults.standard.data(forKey: folderSelectionsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Set<String>].self, from: data)) ?? [:]
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: folderSelectionsKey)
        }
    }
}
