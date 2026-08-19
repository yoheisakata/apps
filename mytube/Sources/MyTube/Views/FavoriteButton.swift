import SwiftUI

/// お気に入り登録/解除トグル(2026-08-14追加)。グリッドのカード・動画リスト・
/// プレイヤー画面のいずれからも同じボタンを使い回す。`FavoritesStore`を直接購読するため
/// 呼び出し側は状態を持つ必要がない。
struct FavoriteButton: View {
    let video: VideoItem
    /// 星の見た目のサイズ。動画カード上のオーバーレイでは小さめ、プレイヤー画面の
    /// 情報行では本文と揃えたサイズにするため呼び出し側で調整できるようにしている。
    var font: Font = .body

    @ObservedObject private var store = FavoritesStore.shared

    private var isFavorite: Bool { store.isFavorite(video) }

    var body: some View {
        Button {
            store.toggle(video)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(font)
                .foregroundStyle(isFavorite ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "お気に入りから外す" : "お気に入りに追加")
    }
}
