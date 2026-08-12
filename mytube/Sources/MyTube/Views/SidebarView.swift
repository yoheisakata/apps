import Foundation
import SwiftUI

/// YouTube の左ナビを模した、ソース(ローカルフォルダ/共有リンク)ごとのネストしたフォルダツリー
/// (Finder サイドバー風のディスクロージャ)。`NavigationSplitView`/`List` は使わない方針
/// (`CLAUDE.md` 参照、独自レイアウト維持のため)なので、既存の `ScrollView { VStack }` の中に
/// 自前の再帰ビュー(`FolderTreeRow`)を組み込む。
///
/// **`OutlineGroup`は使わない**(2026-08-05、当初は`OutlineGroup`で組んでいたが撤去した ―
/// 「サブフォルダはもう少しずらしてほしい」「同じ階層のサブフォルダは同じ横の位置に
/// してほしい」という要望に対応する過程で、`OutlineGroup`の自動インデント・開閉矢印の
/// 予約幅が子の有無によって変わり(子を持つノードの前にだけ矢印ぶんの幅を確保する)、
/// インデント量をこちらから正確に制御できないことが分かったため。`depth`から
/// `CGFloat(depth) * indentUnit`で直接インデント幅を計算する自前の再帰ビューに置き換え、
/// 開閉矢印の枠も子の有無に関わらず常に同じ幅を確保することで、同じ階層のノードが
/// 必ず同じ横位置に揃うようにしている。再度`OutlineGroup`に戻さないこと)。
struct SidebarView: View {
    let localSources: [LocalSource]
    let remoteSources: [RemoteSource]
    @Binding var selectedNode: SidebarSelection?
    /// ソースID(`LocalSource.id`/`RemoteSource.id`)を渡してそのソースをアンロードする
    /// (2026-08-05、「左のライブラリセクションからアンロードしたい」という要望に対応 ―
    /// 以前はトップバーの`OpenSourcesPopover`経由でしか閉じられなかった)。
    let onUnload: (String) -> Void

    /// 展開中のノードID(`FolderTreeNode.id`)の集合。開閉状態は`OutlineGroup`任せではなく
    /// ここで自前管理する(上記の理由で自前の再帰ビューに切り替えたため)。既定は全ノード
    /// 折りたたみ(旧`OutlineGroup`実装のデフォルト挙動を踏襲)。
    @State private var expandedNodeIDs: Set<String> = []

    /// ソースごとに1本ずつツリーを構築する(同名サブフォルダが別ソースにあっても
    /// `sourceID` で区別されるので混ざらない)。「すべての動画」より下のツリー部分を
    /// ローカル/OneDrive/YouTubeの3グループに分ける(2026-08-05、「Local/OneDrive/YouTubeで
    /// グループ分けしてほしい」という要望に対応 ― 以前はソース種別を問わず1本のツリーに
    /// フラットに並べていた)。**「ライブラリ」という見出し自体は出さない**(2026-08-05、
    /// 「ライブラリという表示はいらないかも」という要望に対応 ― 各グループの見出し
    /// (「ローカル」/「OneDrive」/「YouTube」)だけで十分で、共通の親見出しは冗長だった)。
    /// ツリーのノードだけでなく、そのソースの`videos`も一緒に持つ(右クリックメニューの
    /// 「配下をすべてダウンロード」がノード配下の`VideoItem`を`folderPath`で絞り込む必要が
    /// あるが、`FolderTreeNode`自体は`folderPath`しか持たないため ― 2026-08-05追加)。
    ///
    /// **計算プロパティではなく`@State`にキャッシュする**(2026-08-06、パフォーマンス改善 ―
    /// 以前はこの3つを`localSources`/`remoteSources`から毎回組み立てる計算プロパティにして
    /// いたが、`ContentView`は検索欄への入力・並び替え変更・長さフィルターの読み込み状況など
    /// `SidebarView`とは無関係な`@State`が変わるたびにも`body`を再評価するため、そのたびに
    /// 親から`SidebarView`が再構築され`body`が呼ばれる ― 計算プロパティである限り、動画数が
    /// 多い(数百〜数千本)ライブラリでは検索欄に1文字打つたびに`FolderTree.build`
    /// (動画ごとに木を辿る)がフルに再実行され、入力のもたつきの原因になっていた。
    /// `localSources`/`remoteSources`が実際に変わった時(`onChange`、`LocalSource`/
    /// `RemoteSource`の`Equatable`合成が必要 ― `Models.swift`参照)だけ`rebuildGroups()`で
    /// 組み直し、`body`はキャッシュ済みの配列を読むだけにすることで、無関係な再描画からは
    /// 完全に切り離した。
    @State private var localGroups: [(node: FolderTreeNode, videos: [VideoItem])] = []
    @State private var oneDriveGroups: [(node: FolderTreeNode, videos: [VideoItem])] = []
    @State private var youtubeGroups: [(node: FolderTreeNode, videos: [VideoItem])] = []
    private var hasAnySource: Bool { !localGroups.isEmpty || !oneDriveGroups.isEmpty || !youtubeGroups.isEmpty }

    private func rebuildGroups() {
        let start = DispatchTime.now()
        localGroups = localSources.map { (FolderTree.build(sourceID: $0.id, sourceName: $0.name, videos: $0.videos), $0.videos) }
        oneDriveGroups = remoteSources.filter { $0.kind == .oneDrive }
            .map { (FolderTree.build(sourceID: $0.id, sourceName: $0.name, videos: $0.videos), $0.videos) }
        youtubeGroups = remoteSources.filter { $0.kind == .youtube }
            .map { (FolderTree.build(sourceID: $0.id, sourceName: $0.name, videos: $0.videos), $0.videos) }
        Log.sidebar.debug("rebuildGroups (\(Log.elapsedMs(since: start), format: .fixed(precision: 1))ms)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarRow(title: "すべての動画", icon: "house.fill", isSelected: selectedNode == nil) {
                selectedNode = nil
            }
            .padding(.top, 8)

            if hasAnySource {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 「配下をすべてダウンロード」はダウンロードという概念があるリモート
                        // (OneDrive/YouTube)のグループだけに出す(ローカル動画は既にローカルに
                        // あるため対象外 ― 2026-08-05追加)。
                        sourceGroup(title: "ローカル", groups: localGroups, showsDownloadAll: false)
                        sourceGroup(title: "OneDrive", groups: oneDriveGroups, showsDownloadAll: true)
                        sourceGroup(title: "YouTube", groups: youtubeGroups, showsDownloadAll: true)
                    }
                    .padding(.leading, 12)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 220, maxWidth: 260, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .onAppear { rebuildGroups() }
        .onChange(of: localSources) { _ in rebuildGroups() }
        .onChange(of: remoteSources) { _ in rebuildGroups() }
    }

    /// グループ見出し(「ローカル」/「OneDrive」/「YouTube」)+そのグループのツリー1本。
    /// ノードが1件も無いグループは見出しごと出さない(未使用のソース種別で空欄を作らないため)。
    @ViewBuilder
    private func sourceGroup(title: String, groups: [(node: FolderTreeNode, videos: [VideoItem])], showsDownloadAll: Bool) -> some View {
        if !groups.isEmpty {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 1)

            ForEach(groups, id: \.node.id) { group in
                FolderTreeRow(
                    node: group.node,
                    depth: 0,
                    sourceVideos: group.videos,
                    showsDownloadAll: showsDownloadAll,
                    expandedNodeIDs: $expandedNodeIDs,
                    selectedNode: $selectedNode,
                    onUnload: onUnload
                )
            }
        }
    }
}

/// 「すべての動画」専用のシンプルな1行(ツリーの開閉・インデントは持たない)。
private struct SidebarRow: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon {
                    Image(systemName: icon)
                        .frame(width: 20)
                }
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.leading, 2)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// フォルダツリー1行 + (展開中なら)その子を再帰的に描画する。インデント幅・開閉矢印の
/// 予約幅を`depth`から完全に自前計算することで、同じ階層のノードは子の有無に関わらず
/// 必ず同じ横位置に揃う(`SidebarView`冒頭のコメント参照)。
private struct FolderTreeRow: View {
    let node: FolderTreeNode
    let depth: Int
    /// このノードが属するソース全体の動画一覧(`FolderTreeNode`自体は`folderPath`しか
    /// 持たないため、右クリックメニューの「配下をすべてダウンロード」がこのノード配下の
    /// `VideoItem`を絞り込むのに使う ― 2026-08-05追加)。再帰呼び出しでは同じ配列を
    /// そのまま子ノードへ渡す(ソースIDは深さに関わらず不変なため)。
    let sourceVideos: [VideoItem]
    /// 「配下をすべてダウンロード」の右クリックメニューを出すかどうか。ダウンロードという
    /// 概念があるリモート(OneDrive/YouTube)グループの行だけ`true`(`SidebarView.sourceGroup`
    /// が渡す)。
    let showsDownloadAll: Bool
    @Binding var expandedNodeIDs: Set<String>
    @Binding var selectedNode: SidebarSelection?
    let onUnload: (String) -> Void

    @State private var isHovering = false

    /// 1階層ぶんのインデント幅(2026-08-05、「サブフォルダはもう少しずらしてほしい」という
    /// 要望に対応。以前の`OutlineGroup`任せの暗黙のインデント量より明示的に広げてある)。
    private let indentUnit: CGFloat = 20
    /// 開閉矢印の予約幅。子の有無に関わらず常にこの幅を確保し、葉ノードは透明な
    /// プレースホルダーを置くことで兄弟ノードと横位置を揃える。
    private let chevronSlotWidth: CGFloat = 14

    private var hasChildren: Bool { !node.children.isEmpty }
    private var isExpanded: Bool { expandedNodeIDs.contains(node.id) }
    private var selection: SidebarSelection { SidebarSelection(sourceID: node.sourceID, folderPath: node.folderPath) }
    /// このノード(サブフォルダを含む)配下の動画。`ContentView.filteredVideos`と同じ
    /// 「祖先フォルダを選べば配下も全部含む」規約(`folderPath.starts(with:)`)。
    private var videosInSubtree: [VideoItem] {
        sourceVideos.filter { $0.folderPath.starts(with: node.folderPath) }
    }

    /// 配下の動画をまとめてローカル保存キューに投入する(2026-08-05追加、「左のサイドバーで
    /// フォルダを右クリック、そのフォルダ配下をすべてDLする機能」という要望への対応)。
    /// `DownloadStore.startDownloadIfNeeded(for:)`はダウンロード中/済みなら何もしない
    /// ガードを内蔵しているため、同じフォルダに対して複数回呼んでも安全(重複ダウンロードは
    /// 起きない)。並列数を絞るキュー等は設けていない ― 個人利用が前提のこのアプリでは、
    /// フォルダ単位で一気に始めても実用上問題ないと判断した。
    private func downloadAllInSubtree() {
        for video in videosInSubtree {
            DownloadStore.shared.startDownloadIfNeeded(for: video)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedNode = selection
            } label: {
                HStack(spacing: 0) {
                    Spacer(minLength: 0).frame(width: CGFloat(depth) * indentUnit)

                    Group {
                        if hasChildren {
                            Button {
                                if isExpanded {
                                    expandedNodeIDs.remove(node.id)
                                } else {
                                    expandedNodeIDs.insert(node.id)
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: chevronSlotWidth, alignment: .center)

                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        Text(node.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        // アンロードはソースのルート行(サブフォルダではなく開いたフォルダ/
                        // 共有リンク/プレイリストそのもの)だけに出す。
                        if node.folderPath.isEmpty, isHovering {
                            Button {
                                onUnload(node.sourceID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("アンロード")
                        }
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 16)
                    .padding(.vertical, 3)
                    .background(selectedNode == selection ? Color.accentColor.opacity(0.18) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.leading, 2)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .contextMenu {
                if showsDownloadAll {
                    Button {
                        downloadAllInSubtree()
                    } label: {
                        Label("配下をすべてダウンロード", systemImage: "arrow.down.circle")
                    }
                }
            }

            if isExpanded {
                ForEach(node.children) { child in
                    FolderTreeRow(
                        node: child,
                        depth: depth + 1,
                        sourceVideos: sourceVideos,
                        showsDownloadAll: showsDownloadAll,
                        expandedNodeIDs: $expandedNodeIDs,
                        selectedNode: $selectedNode,
                        onUnload: onUnload
                    )
                }
            }
        }
    }
}
