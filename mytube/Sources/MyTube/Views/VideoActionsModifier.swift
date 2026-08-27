import AppKit
import SwiftUI

/// グリッド/一覧/ハイブリッド3表示形式で共通の、動画1本ぶんの操作(右クリックメニュー・
/// command+deleteでの削除・確認ダイアログ)をまとめたViewModifier
/// (2026-08-05、`VideoCardView`にあった実装を切り出したもの)。リモート(OneDrive/YouTube)
/// 動画は`DownloadStore`のローカルコピーだけゴミ箱へ移動できる(共有元のファイルには触れない)。
/// **ローカル動画本体の削除は2026-08-21追加**(ルート`CLAUDE.md`/`mytube/CLAUDE.md`の
/// 「変更時の注意」参照 ― 以前は「ワンクリックで実ファイルが消えるのはリスクが高い」という
/// 判断で直接削除できない設計にしていたが、「ローカルの場合ファイルを削除できる機能が欲しい」
/// という要望を受けて方針を変更し、確認ダイアログ付きでゴミ箱へ移動できるようにした)。
/// `onDeleteLocal`(呼び出し元が渡す、実際のトラッシュ移動+一覧からの除去を行うクロージャ)が
/// `nil`のときは従来通り「Finderで表示」のみを出す。
struct VideoActionsModifier: ViewModifier {
    let video: VideoItem
    /// ホバー中かどうか(呼び出し元が`.onHover`で管理)。command+deleteはホバー中の
    /// カード/行のみに反応させるためのガード。
    let isHovering: Bool
    /// ローカル動画を実際に削除する処理(`ContentView`が提供 ― ファイルをゴミ箱へ移動した上で
    /// `localSources`から取り除く)。`Table`内の行(`VideoTableView`)等、常に渡せるとは限らない
    /// 呼び出し元のために`nil`許容にしてある。
    var onDeleteLocal: ((VideoItem) async throws -> Void)? = nil

    @ObservedObject private var downloadStore = DownloadStore.shared
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteError = false
    @State private var deleteErrorMessage = ""
    /// タグ編集シート(2026-08-22追加、`Views/EpisodeTagEditorView.swift`参照)。
    /// ローカル/リモートいずれの動画でも(ファイル操作を伴わないメタデータのため)出す。
    @State private var showsTagEditor = false

    private var canDeleteLocal: Bool { !video.isRemote && onDeleteLocal != nil }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if video.isRemote {
                    if downloadStore.isDownloaded(video) {
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            Label("ローカルコピーを削除", systemImage: "trash")
                        }
                    }
                } else {
                    Button {
                        revealInFinder()
                    } label: {
                        Label("Finderで表示", systemImage: "folder")
                    }
                    if canDeleteLocal {
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            Label("ファイルを削除", systemImage: "trash")
                        }
                    }
                }
                Button {
                    showsTagEditor = true
                } label: {
                    Label("タグを編集...", systemImage: "tag")
                }
            }
            .sheet(isPresented: $showsTagEditor) {
                EpisodeTagEditorView(video: video, onDone: { showsTagEditor = false })
            }
            .background(
                Button("", action: deleteAction)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .disabled(!isHovering || !(video.isRemote ? downloadStore.isDownloaded(video) : canDeleteLocal))
            )
            .confirmationDialog(
                video.isRemote
                    ? "「\(video.title)」のローカルコピーをゴミ箱に移動しますか?(\(video.remoteKind?.displayName ?? "")の元動画は削除されません)"
                    : "「\(video.title)」をゴミ箱に移動しますか?(元のファイルが削除されます)",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("ゴミ箱に移動", role: .destructive, action: deleteAction)
                Button("キャンセル", role: .cancel) {}
            }
            .alert("削除できませんでした", isPresented: $showsDeleteError) {
                Button("OK") {}
            } message: {
                Text(deleteErrorMessage)
            }
    }

    private func deleteAction() {
        if video.isRemote {
            deleteLocalCopy()
        } else {
            deleteLocalFile()
        }
    }

    private func deleteLocalCopy() {
        Task {
            do {
                try await downloadStore.deleteLocalCopy(for: video)
            } catch {
                deleteErrorMessage = error.localizedDescription
                showsDeleteError = true
            }
        }
    }

    private func deleteLocalFile() {
        guard let onDeleteLocal else { return }
        Task {
            do {
                try await onDeleteLocal(video)
            } catch {
                deleteErrorMessage = error.localizedDescription
                showsDeleteError = true
            }
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([video.url])
    }
}

extension View {
    func videoActions(video: VideoItem, isHovering: Bool, onDeleteLocal: ((VideoItem) async throws -> Void)? = nil) -> some View {
        modifier(VideoActionsModifier(video: video, isHovering: isHovering, onDeleteLocal: onDeleteLocal))
    }
}
