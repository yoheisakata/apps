import SwiftUI

/// 左側のライブラリツリー。「すべての曲」「リンク」+ OneDrive 共有リンクごとのフォルダ階層。
/// mytube の `Views/SidebarView.swift` と同じく `List`/`OutlineGroup` は使わず、
/// インデント幅と開閉矢印スロットを自前で計算する再帰ビュー(`LibraryFolderRow`)で描く
/// ― 同じ階層のノードが子の有無に関わらず必ず同じ横位置に揃うようにするため。
struct LibrarySidebarView: View {
    let allCount: Int
    let linkCount: Int
    let sources: [OneDriveLibrarySource]
    let tracks: [Track]
    @Binding var selection: LibrarySelection
    var onRescan: (String) -> Void
    var onRemoveSource: (String) -> Void

    @State private var expandedNodeIDs: Set<String> = []
    /// フォルダツリーは計算プロパティにせず `@State` にキャッシュする ― `ContentView.body` は
    /// 再生位置の更新で0.5秒ごとに再評価されるため、そのたびに全曲を辿って木を組み直すと
    /// 曲数が多いライブラリで確実に重くなる(mytube の `SidebarView` が踏んだのと同じ問題)。
    @State private var trees: [LibraryNode] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarRow(
                    title: "すべての曲", systemImage: "music.note.list", count: allCount,
                    isSelected: selection == .all, depth: 0
                ) { selection = .all }

                if linkCount > 0 {
                    SidebarRow(
                        title: "リンク", systemImage: "link", count: linkCount,
                        isSelected: selection == .links, depth: 0
                    ) { selection = .links }
                }

                if !sources.isEmpty {
                    Text("OneDrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.bottom, 1)
                        .padding(.horizontal, 8)

                    ForEach(trees) { root in
                        LibraryFolderRow(
                            node: root, depth: 0, isRoot: true,
                            selection: $selection, expandedNodeIDs: $expandedNodeIDs,
                            onRescan: onRescan, onRemoveSource: onRemoveSource
                        )
                    }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
        // 曲の増減(件数)と共有リンクの一覧(名前・曲数)が変わったときだけ組み直す。
        .onAppear { rebuildTrees() }
        .onChange(of: sources) { _ in rebuildTrees() }
        .onChange(of: allCount) { _ in rebuildTrees() }
    }

    private func rebuildTrees() {
        trees = sources.map { LibraryTree.build(source: $0, tracks: tracks) }
    }
}

/// フォルダ1行 + 展開中なら子を再帰的に描く。
private struct LibraryFolderRow: View {
    let node: LibraryNode
    let depth: Int
    let isRoot: Bool
    @Binding var selection: LibrarySelection
    @Binding var expandedNodeIDs: Set<String>
    var onRescan: (String) -> Void
    var onRemoveSource: (String) -> Void

    private var isExpanded: Bool { expandedNodeIDs.contains(node.id) }

    var body: some View {
        SidebarRow(
            title: node.name,
            systemImage: isRoot ? "cloud.fill" : "folder.fill",
            count: nil,
            isSelected: selection == node.selection,
            depth: depth,
            hasChildren: !node.children.isEmpty,
            isExpanded: isExpanded,
            onToggleExpand: {
                if isExpanded { expandedNodeIDs.remove(node.id) } else { expandedNodeIDs.insert(node.id) }
            }
        ) {
            selection = node.selection
        }
        .contextMenu {
            if isRoot {
                Button("再スキャン(新しい曲を取り込む)") { onRescan(node.shareURL) }
                Divider()
                Button("この共有リンクの曲を削除", role: .destructive) { onRemoveSource(node.shareURL) }
            }
        }

        if isExpanded {
            ForEach(node.children) { child in
                LibraryFolderRow(
                    node: child, depth: depth + 1, isRoot: false,
                    selection: $selection, expandedNodeIDs: $expandedNodeIDs,
                    onRescan: onRescan, onRemoveSource: onRemoveSource
                )
            }
        }
    }
}

/// サイドバーの1行(インデント・開閉矢印スロット・アイコン・件数バッジ)。
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int?
    let isSelected: Bool
    let depth: Int
    var hasChildren = false
    var isExpanded = false
    var onToggleExpand: (() -> Void)?
    var onSelect: () -> Void

    private let indentUnit: CGFloat = 14
    private let chevronSlotWidth: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(depth) * indentUnit, height: 1)

            // 子の有無に関わらず同じ幅を確保して、同じ階層の行の横位置を揃える。
            Group {
                if hasChildren {
                    Button {
                        onToggleExpand?()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                }
            }
            .frame(width: chevronSlotWidth)

            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : Color.accentColor.opacity(0.75))
                .frame(width: 14)

            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let count {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
