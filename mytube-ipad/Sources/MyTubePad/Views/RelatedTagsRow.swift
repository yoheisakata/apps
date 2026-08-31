import SwiftUI

/// `ConanEpisodeTags.allTags(for:)`の結果を小さいカプセル型のチップで横並びに表示する
/// (2026-08-27追加、mytube(Mac版)の`Views/RelatedTagsRow.swift`から表示専用チップだけを
/// 移植 ― mytube-ipadは自動タグ表示のみで、Mac版にある押せるタグフィルター
/// (`TagFilterRow`)・手動編集シートは持たない)。`SourceGridView`の`VideoCardView`が
/// タイトル下に使う。
struct RelatedTagsRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

/// `SourceGridView`上部のタグフィルター(2026-08-27追加、mytube(Mac版)の
/// `Views/RelatedTagsRow.swift`の`TagFilterRow`から移植 ― 「タグフィルタしたい」という
/// 要望への対応。当初mytube-ipadは自動タグ表示のみのスコープだったが、この要望を受けて
/// Mac版と同じ押せる・選択状態を持つタグフィルターも追加した)。純粋なSwiftUIのみで
/// 書かれているため、AppKit依存の書き換え無しにそのままiOSでも動く。複数選択時はOR
/// (いずれか1つでも一致すれば表示)。
struct TagFilterRow: View {
    let availableTags: [String]
    @Binding var selectedTags: Set<String>
    /// 「タグなし」フィルター。`selectedTags`とは排他。
    @Binding var showsUntaggedOnly: Bool

    private var hasActiveFilter: Bool { !selectedTags.isEmpty || showsUntaggedOnly }

    var body: some View {
        HStack(spacing: 8) {
            Button("クリア") {
                selectedTags.removeAll()
                showsUntaggedOnly = false
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .disabled(!hasActiveFilter)
            .opacity(hasActiveFilter ? 1 : 0.4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        showsUntaggedOnly.toggle()
                        if showsUntaggedOnly { selectedTags.removeAll() }
                    } label: {
                        Text("タグなし")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(showsUntaggedOnly ? Color.secondary : Color.secondary.opacity(0.15)))
                            .foregroundStyle(showsUntaggedOnly ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    ForEach(availableTags, id: \.self) { tag in
                        let isSelected = selectedTags.contains(tag)
                        Button {
                            showsUntaggedOnly = false
                            if isSelected {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        } label: {
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.15)))
                                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
