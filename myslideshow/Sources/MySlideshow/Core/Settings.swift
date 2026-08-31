import Foundation

/// UserDefaults キーの一元管理(mytubeの`Core/Settings.swift`と同じ方針)。
/// **リンクの追加・削除UI(旧`bookmarks`)は2026-08-29に撤去した** ―
/// 「リンクはめったにかわらないので、ハードコードのままでいい。設定にも追加や削除できなくて
/// いい」という要望を受け、OneDriveリンクは`ContentView.links`に直書きの固定配列(2件:
/// 動画専用の「子どもの動画」・写真専用の「写真」)になった(`Views/SettingsView.swift`/
/// `Views/OpenLinkSheet.swift`ごと削除済み)。
enum Settings {
    private static let photoDurationKey = "myslideshow.photoDurationSeconds"
    private static let shuffleEnabledKey = "myslideshow.shuffleEnabled"
    private static let timeLimitMinutesKey = "myslideshow.timeLimitMinutes"
    private static let folderSelectionsKey = "myslideshow.folderSelections"
    private static let playbackModeKey = "myslideshow.playbackMode"

    /// 写真1枚あたりの表示秒数。既定6秒。
    static var photoDurationSeconds: Double {
        get {
            let value = UserDefaults.standard.double(forKey: photoDurationKey)
            return value > 0 ? value : 6.0
        }
        set { UserDefaults.standard.set(newValue, forKey: photoDurationKey) }
    }

    /// 順番をシャッフルするか。既定はfalse(フォルダ順)。
    static var shuffleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: shuffleEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: shuffleEnabledKey) }
    }

    /// スライドショーの時間制限(分)。**5分刻み**、`nil`(既定)は無制限。
    /// `Views/HomeView.swift`のスライダーが`0`(無制限)〜`Int`の刻みで編集する
    /// (2026-08-29追加、「スライドショーの時間制限を作りたい。スライダーで5分毎の
    /// メモリで最大は無制限」という要望への対応)。
    static var timeLimitMinutes: Int? {
        get {
            let value = UserDefaults.standard.integer(forKey: timeLimitMinutesKey)
            return value > 0 ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: timeLimitMinutesKey) }
    }

    /// スライドショーの表示モード(`Models.PlaybackMode`)。既定は`.fullScreen`
    /// (2026-08-30のモード追加以前からの唯一の挙動だったため、既定値として維持)。
    static var playbackMode: PlaybackMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: playbackModeKey) else { return .fullScreen }
            return PlaybackMode(rawValue: raw) ?? .fullScreen
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: playbackModeKey) }
    }

    /// リンクごとに選んだ、1階層目のサブフォルダ名(「年別」フォルダ等)の集合。
    /// キーは`HardcodedLink.id`(＝URL文字列、ハードコードなので安定)。**動画・写真を
    /// 別々のチェックボックス群にした**(2026-08-29、「動画と写真は別のチェックボックスに
    /// して」という要望への対応 ― 一時期は両リンク共通の1つの値だったが、リンクごとの
    /// 辞書に戻した)。未保存(キー無し)は「全フォルダ対象」を意味する。
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
