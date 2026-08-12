import SwiftUI

/// YouTube のホームフィードを模した動画一覧。表示形式(グリッド/ハイブリッド)を
/// `viewMode`で切り替える(2026-08-05、「MyTubeの動画の表示の仕方を増やしたい」という
/// 要望への対応 ― 以前は`HomeGridView`という名前でグリッド専用だった。当初は
/// グリッド/一覧/ハイブリッドの3種類だったが、一覧とハイブリッドがFinder風の表形式に
/// 統一された結果ほぼ同じ見た目になったため「一覧は削除します」という要望で一覧を廃止した)。
/// グリッド(`VideoCardView`)は自前で`ScrollView`に入れる必要がある単純な`LazyVGrid`だが、
/// ハイブリッド型は`VideoTableView`(`Table`自体がスクロール可能)を使うため`ScrollView`に
/// 入れ子にしない(二重スクロール防止 ― `switch`をトップレベルに出し、`ScrollView`は
/// グリッドの分岐にだけかぶせている)。
struct HomeVideosView: View {
    let videos: [VideoItem]
    let hasFolder: Bool
    let isScanning: Bool
    let viewMode: HomeViewMode
    let onSelect: (VideoItem) -> Void

    // コンパクトに並べる(2026-08-05、「コンパクトに並べて」という要望に対応 ―
    // カードを小さく・間隔を詰めて1画面に入る枚数を増やす)。
    private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)]

    var body: some View {
        if isScanning {
            ScrollView {
                EmptyStateView(
                    icon: "arrow.triangle.2.circlepath",
                    title: "動画を読み込み中…",
                    subtitle: nil
                )
            }
        } else if !hasFolder {
            ScrollView {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    title: "フォルダを選択してください",
                    subtitle: "右上の「フォルダを選択」から動画が入ったフォルダを選ぶか、\nウィンドウにフォルダをドラッグ&ドロップしてください。\nサブフォルダも含めて一覧表示されます。"
                )
            }
        } else if videos.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "video.slash",
                    title: "動画が見つかりません",
                    subtitle: "対応形式: mp4, mov, m4v, avi, mkv, webm, wmv, flv, mpg, mpeg, 3gp"
                )
            }
        } else {
            switch viewMode {
            case .grid: ScrollView { gridBody }
            case .hybrid: VideoTableView(videos: videos, onSelect: onSelect)
            }
        }
    }

    private var gridBody: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(videos) { video in
                VideoCardView(video: video) { onSelect(video) }
            }
        }
        .padding(16)
    }

}

private struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(80)
    }
}
