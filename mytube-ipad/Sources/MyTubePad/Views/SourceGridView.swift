import SwiftUI

/// 選択中のOneDrive共有リンク1本ぶんの動画一覧。中身(グリッド/リスト・フォルダタブ・
/// タグフィルター)は`VideoLibraryView`に委譲し、このビューは共有リンクのスキャン
/// (`onLoad`/`.refreshable`/`.task(id:)`)とナビゲーションタイトルだけを担う
/// (2026-08-27、「ローカルに保存した動画の一覧もほしい」という要望への対応で
/// `VideoLibraryView`を切り出した際に、このビューは薄いラッパーへ縮小した)。
/// `ContentView`が`.id(bookmark.id)`を付けて呼ぶため、別のリンクに切り替えると
/// `VideoLibraryView`の`@State`(表示形式以外)はすべて自動的にリセットされる。
struct SourceGridView: View {
    let bookmark: SharedLinkBookmark
    let source: RemoteSource?
    let onLoad: () async -> Void
    let onPlay: (VideoItem, [VideoItem]) -> Void

    var body: some View {
        VideoLibraryView(
            videos: source?.videos ?? [],
            isLoading: source?.isLoading ?? false,
            errorMessage: source?.errorMessage,
            emptyMessage: "動画が見つかりませんでした",
            onPlay: onPlay,
            selectionAction: .download
        )
        .navigationTitle(bookmark.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // キャッシュ済みの一覧をすでに表示しながら裏でバックグラウンド更新している間
            // (2026-08-28追加、`RemoteListCache`参照)、`VideoLibraryView`側の
            // `isLoading`分岐(一覧が空のときだけの全画面スピナー)は出ないため、代わりに
            // ここに控えめなインジケーターを出す ― 更新中であることが分かるように。
            if source?.isLoading == true {
                ToolbarItem(placement: .navigationBarLeading) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .refreshable {
            await onLoad()
        }
        .task(id: bookmark.id) {
            if source == nil {
                await onLoad()
            }
        }
    }
}
