import SwiftUI

/// 1本の動画のタグを手動で追加・削除するシート(2026-08-22追加、「手動で既存または新規の
/// タグをエピソードに追加できる?」という要望への対応)。`VideoActionsModifier`の右クリック
/// メニュー「タグを編集...」から開く。自動判定(`ConanEpisodeTags`)のタグは削除できない
/// (`EpisodeTagStore`のドキュメント参照 ― 追加のみのスコープ)ため、グレーアウトした
/// バッジとして区別して表示する。
struct EpisodeTagEditorView: View {
    let video: VideoItem
    let onDone: () -> Void

    @ObservedObject private var store = EpisodeTagStore.shared
    @State private var newTagText = ""

    private var autoTags: [String] { ConanEpisodeTags.tags(for: video.title) }
    private var manualTags: [String] { store.manualTags(for: video).sorted() }

    /// 「既存のタグから選ぶ」候補: 定義済み9種 + これまでに他の動画で使われた自由なタグ名。
    /// この動画に既に付いている分は除く。
    private var suggestions: [String] {
        let applied = Set(autoTags + manualTags)
        let all = ConanEpisodeTags.allTags + store.allKnownManualTags
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted && !applied.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("タグを編集")
                .font(.headline)
            Text(video.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !autoTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自動判定(削除不可)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    wrappedChips(autoTags) { tag in
                        chip(tag, isRemovable: false) {}
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("手動で追加したタグ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if manualTags.isEmpty {
                    Text("まだありません")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    wrappedChips(manualTags) { tag in
                        chip(tag, isRemovable: true) { store.removeTag(tag, from: video) }
                    }
                }
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("既存のタグから追加")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    wrappedChips(suggestions) { tag in
                        Button {
                            store.addTag(tag, to: video)
                        } label: {
                            Label(tag, systemImage: "plus")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                    }
                }
            }

            HStack {
                TextField("新しいタグ名", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNewTag)
                Button("追加", action: addNewTag)
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Spacer()
                Button("完了", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func addNewTag() {
        store.addTag(newTagText, to: video)
        newTagText = ""
    }

    @ViewBuilder
    private func wrappedChips<Content: View>(_ tags: [String], @ViewBuilder content: @escaping (String) -> Content) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                content(tag)
            }
        }
    }

    private func chip(_ tag: String, isRemovable: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption.weight(.medium))
            if isRemovable {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(isRemovable ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15)))
        .foregroundStyle(isRemovable ? Color.accentColor : Color.secondary)
    }
}

/// タグチップを折り返して並べるだけの最小限のレイアウト(2026-08-22追加)。SwiftUIの
/// `Layout`プロトコル(macOS 13+)を使う ― `HStack`は折り返さずシート幅をはみ出すため。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
