import Foundation

/// 各話に関連するキャラクター・組織名のタグ付け(2026-08-22追加、「各エピソードで関連の
/// ある項目を書いて(例、黒の組織、怪盗キッド、等)」という要望への対応)。
/// `Core/MainStoryDetector.swift`と同じ方針で、公式のエピソードデータは一切持たず、
/// **タイトル文字列に実際に含まれるキーワード**だけを見て判定する純粋関数 ―
/// キーワードはすべて名探偵コナンの固有名詞(黒の組織/怪盗キッド/警察学校編/安室透/
/// 工藤優作/灰原哀/服部平次)なので、他のジャンルの動画タイトルに偶然含まれる
/// おそれは極めて低い。`VideoCardView`/`VideoTableView`が`video.title`から都度計算して
/// タグが1つ以上あるときだけ表示する(「コナンメインストーリー」チャンネルに限らず、
/// タイトルがキーワードにマッチする動画ならどこに表示されていても出る)。
///
/// **NFC正規化が必須**: macOSのファイル名はUnicode正規化形式D(NFD、濁点等を独立した
/// 結合文字として分解した形)で保存されていることが多く、`VideoItem.title`もそれを
/// そのまま引き継ぐ。ソースコード中のキーワード文字列リテラルは通常NFC(結合済み)の
/// ため、正規化せずに`contains`で比較すると、見た目は同じ「キッド」でも一致しないことが
/// ある(実際に`grep`でこの不一致を踏んで発覚した)。両辺を
/// `precomposedStringWithCanonicalMapping`でNFCに揃えてから比較する。
enum ConanEpisodeTags {
    /// キーワード(複数可、いずれかがタイトルに含まれればマッチ)→タグ名。
    /// **`"京極真"`ルールは2026-08-27に削除した**(「京極のタグは削除」という要望への対応)。
    /// 続けて同日、`"工藤新一"`ルールも削除した(「工藤新一タグは削除」という要望への対応)。
    private static let rules: [(keywords: [String], tag: String)] = [
        (["黒の組織", "黒ずくめ"], "黒の組織"),
        (["キッド"], "怪盗キッド"),
        (["警察学校編"], "警察学校編"),
        (["安室"], "安室透"),
        (["工藤優作"], "工藤優作"),
        (["灰原"], "灰原哀"),
        (["平次"], "服部平次"),
    ]

    /// 定義済みの全タグ名(ルールの定義順)。タグフィルターUI(`Views/RelatedTagsRow.swift`の
    /// `TagFilterRow`)が、実際にそのチャンネルに存在するタグだけを絞り込んで表示する際の
    /// 基準順序として使う(2026-08-22追加、「タグでフィルタもかけられるようにしたい」という
    /// 要望への対応)。
    static let allTags: [String] = rules.map(\.tag)

    static func tags(for title: String) -> [String] {
        let normalizedTitle = title.precomposedStringWithCanonicalMapping
        return rules.compactMap { rule in
            let matched = rule.keywords.contains {
                normalizedTitle.contains($0.precomposedStringWithCanonicalMapping)
            }
            return matched ? rule.tag : nil
        }
    }
}
