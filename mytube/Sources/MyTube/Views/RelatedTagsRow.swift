import SwiftUI

/// `ConanEpisodeTags.tags(for:)`の結果を小さいカプセル型のチップで横並びに表示する
/// (2026-08-22追加)。`VideoCardView`(グリッド、タイトル下)・`VideoTableView`の
/// `NameCell`(ハイブリッド表、タイトルの右)で共有する。
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

/// 「コナンメインストーリー」チャンネル上部のタグフィルター(2026-08-22追加、「タグでも
/// フィルタをかけられるようにしたい」という要望への対応)。`RelatedTagsRow`(カード側の
/// 非インタラクティブな表示専用チップ)とは別に、押せる・選択状態を持つチップとして
/// 独立させている。複数選択時はOR(いずれか1つでも一致すれば表示)― 「黒の組織」と
/// 「怪盗キッド」を両方選べば両方の話数を一度に見られる、という絞り込みではなく
/// 「集める」使い方を優先した。
struct TagFilterRow: View {
    /// そのチャンネルに実在するタグだけ(`ContentView`側で`ConanEpisodeTags.allTags`を
    /// 現在の一覧に絞り込んで渡す)。存在しないタグのボタンを出して押しても何も
    /// 変わらない空振りを避けるため。
    let availableTags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(availableTags, id: \.self) { tag in
                    let isSelected = selectedTags.contains(tag)
                    Button {
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

                if !selectedTags.isEmpty {
                    Button("クリア") { selectedTags.removeAll() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
