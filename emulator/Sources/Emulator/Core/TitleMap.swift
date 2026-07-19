import Foundation

/// 日本語タイトル → ローマ字 No-Intro 名の対照表。
/// libretro-thumbnails はローマ字名しか持たないため、日本語ファイル名の ROM は
/// この表を経由してカバーアートを探す。
/// ファイル: `~/Library/Application Support/RetroGames/title-map.json`
/// 形式: { "NES|日本語タイトル": "No-Intro Name (Japan)", ... }(キーは NFC 正規化)
enum TitleMap {
    static let shared: [String: String] = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent("RetroGames/title-map.json")
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }()

    /// 日本語ファイル名に対応するローマ字名を返す(なければ nil)
    static func romanized(system: GameSystem, japaneseTitle: String) -> String? {
        let key = "\(system.rawValue)|\(japaneseTitle.precomposedStringWithCanonicalMapping)"
        return shared[key]
    }
}
