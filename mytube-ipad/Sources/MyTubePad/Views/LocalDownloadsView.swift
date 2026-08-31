import SwiftUI

/// 「保存済み」一覧(2026-08-27追加、「ローカルに保存した動画の一覧もほしい」という
/// 要望への対応。表示名は当初「ローカル保存済み」だったが、2026-08-28に「『ローカル』と
/// いう表示はいらない」という要望を受けて「保存済み」に短縮した)。`ContentView`の
/// サイドバーで共有リンクとは別枠の特別な行として選べる ―
/// どの共有リンクからダウンロードしたかに関わらず、端末に保存済みの動画を横断して一覧できる。
/// `DownloadStore.shared.localVideos()`(ダウンロード時に永続化したメタデータから
/// `[VideoItem]`を再構成する、`DownloadStore.swift`参照)を`VideoLibraryView`
/// (`SourceGridView`と共通の中身)へそのまま渡すだけの薄いラッパー。`@ObservedObject`で
/// `DownloadStore`を購読しているため、他の画面でダウンロード/削除するたびにこの一覧も
/// 自動的に更新される。
///
/// **1件削除**はVideoLibraryView共通の長押しコンテキストメニュー、**複数削除**は
/// `VideoLibraryView`の複数選択モード(`selectionAction: .delete`)、**全件削除**は
/// このビュー独自のツールバーボタン(2026-08-28追加、「1件削除、複数削除、全件削除を
/// 入れてほしい」という要望への対応)― 全件削除だけは複数選択を経由せず1タップで
/// 済むようにした(全部消したいときに毎回「すべて選択」を押させるのは冗長なため)。
struct LocalDownloadsView: View {
    let onPlay: (VideoItem, [VideoItem]) -> Void

    @ObservedObject private var downloadStore = DownloadStore.shared
    @State private var showsDeleteAllConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // 端末の全体ストレージ状況(2026-08-28追加、「Ipadの全体のストレージ状況も
            // 示してほしい」という要望への対応)。「あとどれくらいダウンロードして
            // 大丈夫か」の目安になるよう、このアプリの保存容量と端末の空き容量を並べて出す。
            StorageSummaryRow(usedByApp: downloadStore.totalDownloadedBytes())
            Divider()
            VideoLibraryView(
                videos: downloadStore.localVideos(),
                isLoading: false,
                errorMessage: nil,
                emptyMessage: "ダウンロード済みの動画はありません",
                onPlay: onPlay,
                selectionAction: .delete,
                showsFullTitle: true
            )
        }
        .navigationTitle("保存済み")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showsDeleteAllConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(downloadStore.localVideos().isEmpty)
                .help("すべて削除")
            }
        }
        .confirmationDialog(
            "ダウンロード済みの動画をすべて削除しますか?",
            isPresented: $showsDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("すべて削除", role: .destructive) {
                downloadStore.deleteAllLocalCopies()
            }
        }
    }
}

/// アプリのダウンロード容量+端末全体の空き/総容量を並べて出す控えめな行(2026-08-28追加)。
private struct StorageSummaryRow: View {
    let usedByApp: Int64

    var body: some View {
        HStack(spacing: 20) {
            summary(label: "このアプリの保存容量", value: ByteCountFormatter.string(fromByteCount: usedByApp, countStyle: .file))
            if let device = DeviceStorage.totalAndFreeBytes() {
                summary(
                    label: "端末の空き容量",
                    value: "\(ByteCountFormatter.string(fromByteCount: device.free, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: device.total, countStyle: .file))"
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func summary(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }
}
