import SwiftUI

/// トップバーの「共有リンクを開く」/「YouTubeプレイリストを開く」ボタンから開くシート。
/// OneDrive共有リンクとYouTubeプレイリストは「登録済み一覧+新規登録フォーム」という
/// 構造が完全に同じ(名前+URLのペアを保存・選択・削除するだけ)のため、1つのビューを
/// `title`/`urlPlaceholder`で出し分けて両方に使う(旧`OpenShareLinkSheet.swift`を
/// 汎用化・改名したもの)。実際の非同期スキャン処理・状態管理は`ContentView`側が持ち、
/// このビューはUIの入出力だけを担う薄いラッパー。
/// `showsNameField`が`false`のとき(YouTube、2026-08-05〜)は名前欄自体を出さず、URLだけで
/// 登録できる ― `ContentView`側がプレイリストのタイトルをyt-dlpから自動取得して名前に使う
/// (「名前は自動取得してほしい」という要望への対応)。OneDriveは共有フォルダ名が
/// 必ずしも分かりやすいとは限らないため、従来通りユーザーが名前を付ける方式を維持している。
struct OpenRemoteLinkSheet: View {
    @Binding var isPresented: Bool
    let title: String
    let urlPlaceholder: String
    var showsNameField: Bool = true
    let bookmarks: [SharedLinkBookmark]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (SharedLinkBookmark) -> Void
    let onDelete: (SharedLinkBookmark) -> Void
    let onAddAndLoad: (String, String) -> Void

    @State private var newName = ""
    @State private var newURL = ""

    private var canAdd: Bool {
        let hasName = !showsNameField || !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName && !newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            if !bookmarks.isEmpty {
                Text("登録済みのリンク")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                List {
                    ForEach(bookmarks) { bookmark in
                        HStack {
                            Button {
                                onSelect(bookmark)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.name)
                                        .font(.body)
                                    Text(bookmark.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)

                            Button {
                                onDelete(bookmark)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: min(CGFloat(bookmarks.count) * 46 + 8, 180))

                Divider()
            }

            Text("新しいリンクを登録")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if showsNameField {
                TextField("名前(例: 実家のPC)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)
            }
            TextField(urlPlaceholder, text: $newURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)
                .onSubmit(addAndLoad)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("読み込み中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { isPresented = false }
                    .disabled(isLoading)
                Button("登録して開く", action: addAndLoad)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoading || !canAdd)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func addAndLoad() {
        guard canAdd else { return }
        onAddAndLoad(newName, newURL)
        newName = ""
        newURL = ""
    }
}
