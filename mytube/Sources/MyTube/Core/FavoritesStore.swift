import Foundation

/// お気に入り登録の状態を持つ`@MainActor ObservableObject`シングルトン(2026-08-14追加、
/// 「チャンネルとして、お気に入りを追加してほしい。リスト時や動画再生時に登録可能に」という
/// 要望への対応)。`Settings.favoriteKeys`(UserDefaults)へ即座に永続化しつつ、`@Published`で
/// グリッド/テーブル/プレイヤー画面すべての星アイコンがリアルタイムに同期して更新されるようにする
/// ― `DownloadStore`と同じ「シングルトン+`@Published`」の設計。
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var keys: Set<String>

    private init() {
        keys = Settings.favoriteKeys
    }

    func isFavorite(_ video: VideoItem) -> Bool {
        keys.contains(video.stableKey)
    }

    func toggle(_ video: VideoItem) {
        if keys.contains(video.stableKey) {
            keys.remove(video.stableKey)
        } else {
            keys.insert(video.stableKey)
        }
        Settings.favoriteKeys = keys
    }
}
