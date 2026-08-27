import Foundation

/// 手動で追加したタグの状態を持つ`@MainActor ObservableObject`シングルトン(2026-08-22追加、
/// 「手動で既存または新規のタグをエピソードに追加できる?」という要望への対応)。
/// `Core/ConanEpisodeTags.swift`の自動判定(タイトルのキーワードだけで決まる純粋関数、
/// 保存の必要が無い)を補う ― 自動判定が拾えなかった話に後からタグを足したり、
/// `ConanEpisodeTags.allTags`に無い自由な名前のタグを作ったりできる。
/// `Core/FavoritesStore.swift`と同じ「シングルトン+`@Published`+即座にUserDefaultsへ
/// 永続化」の設計。**自動判定されたタグを取り消す(除外する)機能は持たない** ―
/// 要望はあくまで「追加」だったため、まずは追加・削除(手動分のみ)に絞ってスコープを
/// 抑えている。
@MainActor
final class EpisodeTagStore: ObservableObject {
    static let shared = EpisodeTagStore()

    @Published private(set) var tagsByKey: [String: Set<String>]

    private init() {
        tagsByKey = Settings.manualEpisodeTags
    }

    func manualTags(for video: VideoItem) -> Set<String> {
        tagsByKey[video.stableKey] ?? []
    }

    /// 表示・フィルター用に、キーワード自動判定(`ConanEpisodeTags.tags(for:)`)・
    /// ユーザー提供の話数別参照データ(`ConanMainStoryReference.tags(forEpisodeRange:)`、
    /// 2026-08-22追加)・手動タグを合わせた一覧を返す。キーワード判定→参照データの順で
    /// 定義順に並べ、手動タグ(それら2つと重複しない分)はあいうえお順で後ろに続ける。
    func allTags(for video: VideoItem) -> [String] {
        var combined = ConanEpisodeTags.tags(for: video.title)
        if let range = ConanMainStoryReference.episodeRange(inTitle: video.title) {
            for tag in ConanMainStoryReference.tags(forEpisodeRange: range) where !combined.contains(tag) {
                combined.append(tag)
            }
        }
        let manualOnly = manualTags(for: video).subtracting(combined).sorted()
        return combined + manualOnly
    }

    func addTag(_ tag: String, to video: VideoItem) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tagsByKey[video.stableKey, default: []].insert(trimmed)
        Settings.manualEpisodeTags = tagsByKey
    }

    func removeTag(_ tag: String, from video: VideoItem) {
        tagsByKey[video.stableKey]?.remove(tag)
        if tagsByKey[video.stableKey]?.isEmpty == true {
            tagsByKey.removeValue(forKey: video.stableKey)
        }
        Settings.manualEpisodeTags = tagsByKey
    }

    /// これまでに手動で(どれかの動画に)使われたことのある全タグ名、あいうえお順
    /// (2026-08-22追加)。タグ編集シート(`Views/EpisodeTagEditorView.swift`)が
    /// 「既存のタグから選ぶ」候補として使う ― `ConanEpisodeTags.allTags`(自動判定の
    /// 固定9種)とは別に、ユーザーが作った自由なタグ名も別の動画で再利用できるようにする。
    var allKnownManualTags: [String] {
        Set(tagsByKey.values.flatMap { $0 }).sorted()
    }
}
