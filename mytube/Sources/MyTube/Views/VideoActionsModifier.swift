import AppKit
import SwiftUI

/// グリッド/一覧/ハイブリッド3表示形式で共通の、動画1本ぶんの操作(右クリックメニュー・
/// command+deleteでのローカルコピー削除・確認ダイアログ)をまとめたViewModifier
/// (2026-08-05、`VideoCardView`にあった実装を切り出したもの)。削除まわりの方針は
/// 全表示形式で同じ: ローカル動画本体は直接削除できない(Finderで表示のみ)、リモート
/// (OneDrive/YouTube)動画は`DownloadStore`のローカルコピーだけゴミ箱へ移動できる
/// (ルート`CLAUDE.md`/`mytube/CLAUDE.md`の「変更時の注意」参照)。
struct VideoActionsModifier: ViewModifier {
    let video: VideoItem
    /// ホバー中かどうか(呼び出し元が`.onHover`で管理)。command+deleteはホバー中の
    /// カード/行のみに反応させるためのガード。
    let isHovering: Bool

    @ObservedObject private var downloadStore = DownloadStore.shared
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteError = false
    @State private var deleteErrorMessage = ""

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
                }
            }
            .background(
                Button("", action: deleteLocalCopy)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .disabled(!isHovering || !video.isRemote || !downloadStore.isDownloaded(video))
            )
            .confirmationDialog(
                "「\(video.title)」のローカルコピーをゴミ箱に移動しますか?(\(video.remoteKind?.displayName ?? "")の元動画は削除されません)",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("ゴミ箱に移動", role: .destructive, action: deleteLocalCopy)
                Button("キャンセル", role: .cancel) {}
            }
            .alert("削除できませんでした", isPresented: $showsDeleteError) {
                Button("OK") {}
            } message: {
                Text(deleteErrorMessage)
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

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([video.url])
    }
}

extension View {
    func videoActions(video: VideoItem, isHovering: Bool) -> some View {
        modifier(VideoActionsModifier(video: video, isHovering: isHovering))
    }
}
