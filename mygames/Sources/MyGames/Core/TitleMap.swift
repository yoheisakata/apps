import Foundation

/// 日本語タイトル → ローマ字 No-Intro 名の対照表。
/// libretro-thumbnails はローマ字名しか持たないため、日本語ファイル名の ROM は
/// この表を経由してカバーアートを探す。
/// 旧 7z コレクション由来で再生成不可のため、リポジトリ (`mygames/title-map.json`) を
/// 正本として git 管理し、ビルド時に同梱したコピーをフォールバックとして使う。
/// 形式: { "NES|日本語タイトル": "No-Intro Name (Japan)", ... }(キーは NFC 正規化)
enum TitleMap {
    static let sourceURL = URL(fileURLWithPath:
        NSString(string: "~/github/apps/mygames/title-map.json").expandingTildeInPath)

    static let shared: [String: String] = {
        var data = try? Data(contentsOf: sourceURL)
        if data == nil, let bundled = Bundle.main.url(forResource: "title-map", withExtension: "json") {
            data = try? Data(contentsOf: bundled)
        }
        guard let data, let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
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
