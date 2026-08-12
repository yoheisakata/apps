import SwiftUI

/// ハイブリッド型(一覧表示、2026-08-05追加。当初はグリッド/一覧/ハイブリッドの3種類が
/// あり、一覧=サムネイル無しのファイル名一覧、ハイブリッド=小さいサムネイル+ファイル名の
/// `LazyVStack`という別々の実装だったが、「Finderのように見やすくしてほしい」→
/// 「ハイブリッド表示も一覧と同様に見やすくして」という2段階の要望を受けて共通の`Table`
/// (AppKitの`NSTableView`をラップしたSwiftUI標準コンポーネント)ベースの表形式に統合 →
/// 統合の結果ほぼ同じ見た目になった一覧型は「一覧は削除します」という要望で廃止し、
/// このハイブリッド型(小さいサムネイル付き)だけが残った)。名前(小さいサムネイル+
/// ファイル名)・長さ・ソース(ローカル/OneDrive/YouTube)・チャンネルの4列を`TableColumn`で
/// 定義するだけで、ヘッダー行・交互の背景色・選択ハイライトといったFinderのリスト表示
/// そのものの見た目がSwiftUI側から自動的に得られる(独自にストライプ背景等を描画する必要は
/// ない)。**`Table`自体がスクロール可能な`NSScrollView`を内包する**ため、`HomeVideosView`側
/// ではこれを`ScrollView`に入れ子にしない(二重スクロールになり操作感が壊れるため ―
/// `HomeVideosView.body`参照)。
struct VideoTableView: View {
    let videos: [VideoItem]
    let onSelect: (VideoItem) -> Void

    /// 単一選択のみ。Finder本来の「選択してから別操作」というワークフローは持たず、選択即
    /// 再生のトリガーとして使うだけなので複数選択のUIは不要。
    @State private var selection: VideoItem.ID?

    var body: some View {
        Table(videos, selection: $selection) {
            TableColumn("名前") { video in
                HStack(spacing: 8) {
                    // 一覧性を優先してごく小さく(2026-08-05、「サムネイルはもう少し
                    // 小さくて良い」という要望に対応 ― 旧`VideoHybridRowView`の幅96より
                    // 詰めている)。長さバッジは狭いサムネイルに重なって見づらいため出さない
                    // (下の「長さ」列に表示)。
                    VideoThumbnailView(video: video, width: 56, cornerRadius: 4, showsDurationBadge: false)
                    Text(video.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // 右クリックメニュー(Finderで表示/ローカルコピーを削除)+確認ダイアログは
                // グリッド型と共通の`VideoActionsModifier`を使い回す。Table内では行のホバー
                // 状態を素直に拾えないため`isHovering`は常にfalse ― command+deleteでの
                // 即時削除だけはこの形式では効かない(右クリック/確認ダイアログ経由の削除は
                // グリッド型と同じく使える)。
                .videoActions(video: video, isHovering: false)
                .pointingHandOnHover()
            }
            .width(min: 280, ideal: 520)

            TableColumn("長さ") { video in
                DurationCell(video: video)
            }
            .width(min: 56, ideal: 64)

            TableColumn("ソース") { video in
                Text(video.remoteKind?.displayName ?? "ローカル")
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("チャンネル") { video in
                Text(video.channel)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
        }
        // 単一クリックで即再生する(グリッド型と同じ「1クリックで開く」操作感に揃えるため ―
        // Finder本来の「シングルクリックで選択・ダブルクリックで開く」とはあえて違えている)。
        // 選択後は`ContentView`側で`selectedVideo`が非nilになり`HomeVideosView`自体が
        // 視聴画面に置き換わるため、選択状態を明示的にクリアする必要はない。
        .onChange(of: selection) { newValue in
            guard let newValue, let video = videos.first(where: { $0.id == newValue }) else { return }
            onSelect(video)
        }
    }
}

/// 「長さ」列の1セル。サムネイルの読み込み(`VideoThumbnailView`)とは独立に
/// `ThumbnailStore`から長さだけを取得する ― `VideoThumbnailView`側も同じキャッシュを
/// 参照するため、どちらが先に読み込んでも二重にデコードすることはない(`cachedDuration`が
/// ヒットすればそちらを使う)。
private struct DurationCell: View {
    let video: VideoItem

    @State private var duration: TimeInterval?

    var body: some View {
        Text(duration.map(VideoThumbnailView.formatDuration) ?? "—")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .task(id: video.id) {
                if let cached = ThumbnailStore.shared.cachedDuration(for: video) {
                    duration = cached
                    return
                }
                duration = await ThumbnailStore.shared.loadDuration(for: video)
            }
    }
}
