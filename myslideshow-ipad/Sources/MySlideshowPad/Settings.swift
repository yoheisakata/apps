import Foundation

/// UserDefaults キーの一元管理(myslideshow(Mac版)の`Core/Settings.swift`と同じ方針)。
/// キーは`myslideshowpad.`プレフィックス(Mac版の`myslideshow.`と衝突しないよう、別アプリ
/// なので当然だが明示)。**`playbackMode`はここには無い** ― ウィンドウ内/全画面/PIPは
/// macOSのウィンドウ管理専用の概念で、iPadは常にフルスクリーンのため対応物が無い。
enum Settings {
    private static let photoDurationKey = "myslideshowpad.photoDurationSeconds"
    private static let shuffleEnabledKey = "myslideshowpad.shuffleEnabled"
    private static let timeLimitMinutesKey = "myslideshowpad.timeLimitMinutes"
    private static let folderSelectionsKey = "myslideshowpad.folderSelections"

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
    static var timeLimitMinutes: Int? {
        get {
            let value = UserDefaults.standard.integer(forKey: timeLimitMinutesKey)
            return value > 0 ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: timeLimitMinutesKey) }
    }

    /// リンクごとに選んだ、1階層目のサブフォルダ名(「年別」フォルダ等)の集合。
    /// キーは`HardcodedLink.id`(＝URL文字列、ハードコードなので安定)。未保存(キー無し)は
    /// 「全フォルダ対象」を意味する。
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
