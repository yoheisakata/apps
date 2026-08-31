import Foundation

/// 名探偵コナンのライブラリ内で、動画がTVシリーズ本編か劇場版(映画)かを、タイトルの
/// 話数トークンだけから判定する純粋関数(2026-08-27追加、mytube(Mac版)の
/// `Core/ConanContentKind.swift`から移植 ― 「TV、Movieもわけられてない」という要望への
/// 対応)。`ConanEpisodeTags`/`ConanMainStoryReference`と同じ「ファイル名の付け方だけを見る」
/// 方針 ― 公式データは持たない。`Views/SourceGridView.swift`の種類フィルター(すべて/TV/映画)
/// が使う。
enum ConanContentKind {
    case tv
    case movie

    static func classify(title: String) -> ConanContentKind? {
        let components = title.components(separatedBy: " - ")
        guard components.count >= 2 else { return nil }
        let token = components[1]
        if token == "映画" || token == "Movie" { return .movie }
        if looksLikeTVEpisodeToken(token) { return .tv }
        return nil
    }

    private static func looksLikeTVEpisodeToken(_ token: String) -> Bool {
        if parseNumericRange(token) != nil { return true }
        if token == "Special" { return true }
        if token.hasPrefix("SP"), Int(token.dropFirst(2)) != nil { return true }
        return false
    }

    private static func parseNumericRange(_ token: String) -> (start: Int, end: Int)? {
        let parts = token.split(separator: "-")
        switch parts.count {
        case 1:
            guard let value = Int(parts[0]) else { return nil }
            return (value, value)
        case 2:
            guard let start = Int(parts[0]), let end = Int(parts[1]) else { return nil }
            return (start, end)
        default:
            return nil
        }
    }

    /// 表示用にタイトルの冗長な接頭辞を取り除く(2026-08-27追加、「TV/映画一覧のときは
    /// 番組名があきらかなので非表示にしたい」という要望への対応)。**あくまで表示専用** ―
    /// `ConanEpisodeTags`/`ConanMainStoryReference`のタグ判定・話数パースは元の
    /// `video.title`をそのまま使い続ける必要があるため、この関数の戻り値をそちらへ渡さないこと
    /// (`Views/SourceGridView.swift`の`Text`表示にだけ使う)。
    /// - TV本編: 「名探偵コナン - 0130 - タイトル - 前編」→「0130 - タイトル - 前編」
    ///   (先頭の番組名だけを外し、話数以降はそのまま残す)。
    /// - 劇場版: 「名探偵コナン - 映画 - 01 - タイトル - 1997」→「01 - タイトル - 1997」
    ///   (番組名+「映画」トークンの2つをまとめて外す。`conan/tv/Special`に混在する
    ///   クロスオーバー作品「名探偵コナン - Movie - タイトル」も同様に先頭2つを外す)。
    /// - 分類できないタイトル(コナン以外、または想定外の形式)はそのまま返す。
    static func displayTitle(for title: String) -> String {
        let components = title.components(separatedBy: " - ")
        switch classify(title: title) {
        case .tv:
            guard components.count >= 2 else { return title }
            return components.dropFirst(1).joined(separator: " - ")
        case .movie:
            guard components.count >= 3 else { return title }
            return components.dropFirst(2).joined(separator: " - ")
        case nil:
            return title
        }
    }
}
