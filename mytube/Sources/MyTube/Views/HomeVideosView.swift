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
    /// 複数選択モード(2026-08-21追加、「複数選択もほしい」という要望への対応)。
    /// `TopBarView`のトグルで`ContentView`が管理する。
    @Binding var isSelectionMode: Bool
    @Binding var selectedIDs: Set<VideoItem.ID>
    /// ローカル動画を1本削除する処理(`ContentView`提供、ファイルをゴミ箱へ移動して
    /// `localSources`から取り除く)。カード/行の右クリックメニュー・command+deleteから使う。
    let onDeleteLocal: (VideoItem) async throws -> Void
    /// 選択中の動画をまとめて削除する確認ダイアログを開く(実削除は`ContentView`側で行う ―
    /// 削除後に`localSources`を書き換える必要があるため)。
    let onRequestDeleteSelected: () -> Void
    /// タグフィルター(2026-08-22追加、2026-08-27に全チャンネル共通へ拡張)。`ContentView`が
    /// 現在表示中の一覧にconanのタグを持つ動画が1件でもあるときだけ`true`+タグ一覧を渡す
    /// (`ConanEpisodeTags`はconan以外のライブラリには基本マッチしないため、無関係な
    /// フォルダでは自然にタグフィルターが出ない)。グリッド・ハイブリッドどちらの表示形式
    /// でも`content`より前に描画するため、両方で使える。
    let showsTagFilter: Bool
    let availableTags: [String]
    @Binding var selectedTags: Set<String>
    @Binding var showsUntaggedOnly: Bool

    // コンパクトに並べる(2026-08-05、「コンパクトに並べて」という要望に対応 ―
    // カードを小さく・間隔を詰めて1画面に入る枚数を増やす。2026-08-27、「サムネイル
    // もう少しちいさくていい」という要望を受けてさらに一段階小さくした)。
    private let gridColumns = [GridItem(.adaptive(minimum: 130, maximum: 165), spacing: 10)]

    /// 選択中のうち実際に削除できる(ローカルの)件数。リモート動画は`VideoCardView`/
    /// `NameCell`側でそもそも選択トグルを無視するため、通常は`selectedIDs`全体と一致する。
    private var selectedLocalCount: Int {
        videos.filter { selectedIDs.contains($0.id) && !$0.isRemote }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSelectionMode {
                selectionToolbar
                Divider()
            }
            if showsTagFilter, !availableTags.isEmpty {
                TagFilterRow(availableTags: availableTags, selectedTags: $selectedTags, showsUntaggedOnly: $showsUntaggedOnly)
                Divider()
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
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
            case .hybrid:
                VideoTableView(
                    videos: videos,
                    onSelect: onSelect,
                    isSelectionMode: isSelectionMode,
                    selectedIDs: selectedIDs,
                    onToggleSelect: toggleSelection,
                    onDeleteLocal: onDeleteLocal
                )
            }
        }
    }

    private var gridBody: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(videos) { video in
                VideoCardView(
                    video: video,
                    action: { onSelect(video) },
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedIDs.contains(video.id),
                    onToggleSelect: { toggleSelection(video) },
                    onDeleteLocal: onDeleteLocal
                )
            }
        }
        .padding(16)
    }

    /// 選択モード中のツールバー ― 選択件数の表示、全解除、削除、選択モードの終了。
    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Text(selectedIDs.isEmpty ? "動画を選択してください" : "\(selectedIDs.count)件選択中")
                .foregroundStyle(.secondary)
            Spacer()
            Button("すべて解除") { selectedIDs.removeAll() }
                .disabled(selectedIDs.isEmpty)
            Button(role: .destructive, action: onRequestDeleteSelected) {
                Label("削除(\(selectedLocalCount))", systemImage: "trash")
            }
            .disabled(selectedLocalCount == 0)
            Button("完了") {
                isSelectionMode = false
                selectedIDs.removeAll()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func toggleSelection(_ video: VideoItem) {
        if selectedIDs.contains(video.id) {
            selectedIDs.remove(video.id)
        } else {
            selectedIDs.insert(video.id)
        }
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
