import Foundation

/// 最近再生した動画の履歴を持つ`@MainActor ObservableObject`シングルトン(2026-08-14追加、
/// 「チャンネルとして、最近再生したビデオを追加してほしい」という要望への対応)。
/// `ContentView`が`selectedVideo`が新しい動画に変わるたびに`recordPlayed(_:)`を呼び、
/// 新しい順の配列として`Settings.recentlyPlayedKeys`へ永続化する。件数は`maxCount`で
/// 上限を設ける(無制限に溜め続けないようにするため ― `DownloadStore`のキャッシュ上限と
/// 似た考え方だが、こちらは単なるキー配列なので上限もずっと小さい)。
@MainActor
final class RecentlyPlayedStore: ObservableObject {
    static let shared = RecentlyPlayedStore()
    static let maxCount = 50

    /// 新しい順(先頭が最新)の`VideoItem.stableKey`一覧。
    @Published private(set) var orderedKeys: [String]

    private init() {
        orderedKeys = Settings.recentlyPlayedKeys
    }

    func recordPlayed(_ video: VideoItem) {
        let key = video.stableKey
        orderedKeys.removeAll { $0 == key }
        orderedKeys.insert(key, at: 0)
        if orderedKeys.count > Self.maxCount {
            orderedKeys.removeLast(orderedKeys.count - Self.maxCount)
        }
        Settings.recentlyPlayedKeys = orderedKeys
    }
}
