import Foundation

/// 各話に関連するキャラクター・組織名のタグ付け(2026-08-27追加、mytube(Mac版)の
/// `Core/ConanEpisodeTags.swift`から移植)。公式のエピソードデータは一切持たず、
/// **タイトル文字列に実際に含まれるキーワード**だけを見て判定する純粋関数 ―
/// キーワードはすべて名探偵コナンの固有名詞なので、他のジャンルの動画タイトルに偶然
/// 含まれるおそれは極めて低い。`SourceGridView`の`VideoCardView`が`video.title`から
/// 都度計算し、タグが1つ以上あるときだけ表示する。
///
/// **NFC正規化が必須**: ファイル名はUnicode正規化形式D(NFD)で保存されていることが
/// 多く、`VideoItem.title`もそれをそのまま引き継ぐ。ソースコード中のキーワード文字列
/// リテラルは通常NFC(結合済み)のため、正規化せずに`contains`で比較すると一致しないことが
/// ある。両辺を`precomposedStringWithCanonicalMapping`でNFCに揃えてから比較する。
enum ConanEpisodeTags {
    /// mytube(Mac版)側で2026-08-27に`"京極真"`・`"工藤新一"`ルールが削除された
    /// (「京極のタグは削除」「工藤新一タグは削除」という要望への対応)ため、それに
    /// 合わせてこちらも同じルール一覧に揃えている。
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
    /// `TagFilterRow`)が、実際に一覧に存在するタグだけを絞り込んで表示する際の基準順序として
    /// 使う(2026-08-27追加、mytube Mac版の`ConanEpisodeTags.allTags`と同じ役割 ―
    /// 名前の衝突を避けるため`allTags(for:)`とは別に`definedTagNames`とした)。
    static let definedTagNames: [String] = rules.map(\.tag)

    static func tags(for title: String) -> [String] {
        let normalizedTitle = title.precomposedStringWithCanonicalMapping
        return rules.compactMap { rule in
            let matched = rule.keywords.contains {
                normalizedTitle.contains($0.precomposedStringWithCanonicalMapping)
            }
            return matched ? rule.tag : nil
        }
    }

    /// キーワード自動判定+`ConanMainStoryReference`の話数別参照データを合わせたタグ一覧
    /// (mytube Mac版の`EpisodeTagStore.allTags(for:)`から、手動タグ部分を除いたもの ―
    /// mytube-ipadは自動タグ表示のみで手動編集機能は持たない)。
    static func allTags(for title: String) -> [String] {
        var combined = tags(for: title)
        if let range = ConanMainStoryReference.episodeRange(inTitle: title) {
            for tag in ConanMainStoryReference.tags(forEpisodeRange: range) where !combined.contains(tag) {
                combined.append(tag)
            }
        }
        return combined
    }
}
