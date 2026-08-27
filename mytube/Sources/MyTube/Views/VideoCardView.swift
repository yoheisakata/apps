import SwiftUI

/// ホームグリッドの1枚のカード。YouTube のサムネイルカードを模す
/// (サムネイル16:9 + 長さバッジ + タイトル)。サムネイル本体は`VideoThumbnailView`、
/// 右クリックメニュー・command+deleteでの削除は`VideoActionsModifier`に切り出してあり、
/// 一覧型(`VideoListRowView`)・ハイブリッド型(`VideoHybridRowView`)と共有する。
struct VideoCardView: View {
    let video: VideoItem
    let action: () -> Void
    /// 複数選択モード(2026-08-21追加、「複数選択もほしい」という要望への対応)。オンの間は
    /// カード全体のタップが再生ではなく選択トグルになり、左上にチェックマークを出す。
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: () -> Void = {}
    /// ローカル動画を実際に削除する処理(`HomeVideosView`経由で`ContentView`から渡る)。
    var onDeleteLocal: ((VideoItem) async throws -> Void)? = nil

    @State private var isHovering = false
    /// タグ(自動判定+手動追加、2026-08-22追加)。`FavoriteButton`と同じ理由で
    /// `EpisodeTagStore`を直接購読する ― 右クリックメニュー「タグを編集...」での追加・
    /// 削除が即座にカードへ反映されるようにするため。
    @ObservedObject private var tagStore = EpisodeTagStore.shared

    /// 関連タグ(2026-08-22追加、`Core/ConanEpisodeTags.swift`/`Core/EpisodeTagStore.swift`
    /// 参照)。黒の組織/怪盗キッド等の自動判定+手動タグを合わせたものを1個以上表示する ―
    /// 「コナンメインストーリー」チャンネルに限らず、タグがある動画ならどこに表示されて
    /// いても出る。
    private var relatedTags: [String] { tagStore.allTags(for: video) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 選択モード中、リモート動画は削除対象外なのでタップに反応させない
            // (`VideoActionsModifier`側は`onDeleteLocal`がnil同然になるためリモートの
            // 「ローカルコピーを削除」メニューだけは引き続き使える)。
            Button(action: isSelectionMode ? (video.isRemote ? {} : onToggleSelect) : action) {
                VStack(alignment: .leading, spacing: 8) {
                    VideoThumbnailView(video: video)

                    // サムネイル下はファイル名だけ(2026-08-05、「コンパクトに並べて」という
                    // 要望に対応 ― 以前はチャンネル名・更新日も出していた)。
                    Text(video.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !relatedTags.isEmpty {
                        RelatedTagsRow(tags: relatedTags)
                    }
                }
            }
            .buttonStyle(.plain)
            // グリッド表示では「ローカルに保存」トグルは出さない(2026-08-05、一度カード下に
            // 追加したが「グリッド表示のときはローカルDLのトグルは表示いらない」という要望を
            // 受けて撤回 ― `LocalSaveToggle`は視聴画面(`PlayerPaneView`のサイドバー)のみで使う。
            // ダウンロード状態自体は引き続き`VideoThumbnailView`のサムネイル左上バッジ
            // (`DownloadBadge`)で見える)。
            .videoActions(video: video, isHovering: isHovering, onDeleteLocal: onDeleteLocal)
            .pointingHandOnHover()

            // お気に入りボタン(2026-08-14追加)。サムネイル左上の`DownloadBadge`と衝突しない
            // よう右上に置く ― カード全体を覆う`Button`とは別のボタンとして`ZStack`で重ねる
            // (`Button`の中に別の`Button`を入れると内側のタップがカード全体のクリックとして
            // 拾われてしまうことがあるため、兄弟として重ねている)。選択モード中は選択操作の
            // 邪魔になるため出さない。
            if !isSelectionMode {
                FavoriteButton(video: video, font: .callout)
                    .padding(6)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .padding(6)
            }
        }
        // 選択チェックマーク(2026-08-21追加)。リモート動画は削除機能の対象外のため薄く
        // 表示し操作できないことを示す。
        // **単なる`Image`ではなく`Button`にする**(2026-08-21修正、「選択モードでラジオ
        // ボタンを押しても選択されない」というユーザー報告への対応)。以前は非インタラクティブな
        // `Image`を`.overlay`でカード全体の`Button`の上に重ねていただけだったため、
        // アイコンの不透明な背景円(`Circle().fill(.black.opacity(0.35))`)がヒットテストの
        // 最前面を占有してしまい、その領域をタップしても下の`Button`にタップが伝わらず、
        // かといってアイコン自身にはアクション(ジェスチャー)が無いため何も起きない
        // 「死んだタップ領域」になっていた。上記の`FavoriteButton`が兄弟として独立した
        // `Button`にすることで確実にタップを拾えているのと同じ理由で、こちらも独立した
        // `Button`に変える。
        .overlay(alignment: .topLeading) {
            if isSelectionMode {
                Button(action: onToggleSelect) {
                    Image(systemName: video.isRemote ? "circle.dashed" : (isSelected ? "checkmark.circle.fill" : "circle"))
                        .font(.title3)
                        .foregroundStyle(video.isRemote ? Color.secondary : (isSelected ? Color.accentColor : Color.white.opacity(0.9)))
                        .background(Circle().fill(.black.opacity(0.35)))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .disabled(video.isRemote)
                .help(video.isRemote ? "リモート動画はここでは削除できません" : "")
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
