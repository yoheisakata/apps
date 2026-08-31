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

/// ホーム画面上部のタグフィルター(2026-08-22追加、「タグでもフィルタをかけられるように
/// したい」という要望への対応。当初は「コナンメインストーリー」チャンネル専用だったが、
/// 2026-08-27に「タグフィルタができない」「ハイブリッドビューモードでタグフィルタしたい」
/// という要望を受け、conanのタグを持つ動画が1件でもある一覧なら、フォルダ/お気に入り/
/// コナンメインストーリーのどれを見ていてもグリッド・ハイブリッド両方の
/// 表示形式で使えるよう`ContentView`側を拡張した ― このビュー自体は変更していない)。
/// `RelatedTagsRow`(カード側の非インタラクティブな表示専用チップ)とは別に、押せる・
/// 選択状態を持つチップとして独立させている。複数選択時はOR(いずれか1つでも一致すれば
/// 表示)― 「黒の組織」と「怪盗キッド」を両方選べば両方の話数を一度に見られる、という
/// 絞り込みではなく「集める」使い方を優先した。
struct TagFilterRow: View {
    /// 現在表示中の一覧に実在するタグだけ(`ContentView`側で`ConanEpisodeTags.allTags`を
    /// 現在の一覧に絞り込んで渡す)。存在しないタグのボタンを出して押しても何も
    /// 変わらない空振りを避けるため。
    let availableTags: [String]
    @Binding var selectedTags: Set<String>
    /// 「タグなし」フィルター(2026-08-27追加、「タグなしをフィルタで一覧にしたい」という
    /// 要望への対応)。実在のタグを1つも持たない話だけに絞り込む、他のタグ選択とは排他の
    /// 特殊モード ― ある話が「黒の組織タグを持つ」と「タグを1つも持たない」を同時に
    /// 満たすことはあり得ないため、通常のタグ選択(OR)とは別のオン/オフとして扱う。
    @Binding var showsUntaggedOnly: Bool

    private var hasActiveFilter: Bool { !selectedTags.isEmpty || showsUntaggedOnly }

    var body: some View {
        HStack(spacing: 8) {
            // クリアはタグと一緒に横スクロールさせず、常に一番左に固定表示する
            // (2026-08-27、「クリアボタンは一番左に固定して」という要望への対応 ―
            // 以前はタグの後ろ(スクロール内の末尾)にあり、タグ数が多いと右へスクロール
            // しないと押せなかった。さらに選択が無いときはボタンごと消えていたため
            // 「クリア機能がなくなってる」という報告を受け、選択の有無に関わらず常時
            // 表示したまま`disabled`で押せる/押せないだけを切り替える形にした)。
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
