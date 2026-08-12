import SwiftUI

/// ホームグリッドの1枚のカード。YouTube のサムネイルカードを模す
/// (サムネイル16:9 + 長さバッジ + タイトル)。サムネイル本体は`VideoThumbnailView`、
/// 右クリックメニュー・command+deleteでの削除は`VideoActionsModifier`に切り出してあり、
/// 一覧型(`VideoListRowView`)・ハイブリッド型(`VideoHybridRowView`)と共有する。
struct VideoCardView: View {
    let video: VideoItem
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                VideoThumbnailView(video: video)

                // サムネイル下はファイル名だけ(2026-08-05、「コンパクトに並べて」という
                // 要望に対応 ― 以前はチャンネル名・更新日も出していた)。
                Text(video.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(.plain)
        // グリッド表示では「ローカルに保存」トグルは出さない(2026-08-05、一度カード下に
        // 追加したが「グリッド表示のときはローカルDLのトグルは表示いらない」という要望を
        // 受けて撤回 ― `LocalSaveToggle`は視聴画面(`PlayerPaneView`のサイドバー)のみで使う。
        // ダウンロード状態自体は引き続き`VideoThumbnailView`のサムネイル左上バッジ
        // (`DownloadBadge`)で見える)。
        .videoActions(video: video, isHovering: isHovering)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        // `Button`の内側では`.onHover` + `NSCursor.push()/pop()`が効かなかったため
        // (`Views/PointingHandCursor.swift`のドキュメント参照)、AppKitのカーソル矩形
        // システムに直接登録する`pointingHandOnHover()`を使う。
        .pointingHandOnHover()
    }
}
