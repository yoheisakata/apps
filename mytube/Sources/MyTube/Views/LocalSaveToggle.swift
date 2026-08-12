import SwiftUI

/// OneDrive動画の「ローカルに保存」トグル(2026-08-05追加、「OneDriveの場合はローカルに
/// 保存はトグルにする。デフォルトではローカルダウンロードはOff」という要望への対応)。
/// `PlayerPaneView`の`infoSidebar`だけで使う ― 当初はホームグリッドの`VideoCardView`にも
/// カード用の省スペース表示(`compact`パラメータ)を出していたが、「グリッド表示のときは
/// ローカルDLのトグルは表示いらない」という要望を受けて撤回した(2026-08-05。グリッド側の
/// ダウンロード状態表示は`VideoThumbnailView`の`DownloadBadge`のみに戻している)。
/// 永続化された専用の状態は持たず、`DownloadStore.state(for:)`(`.notDownloaded`/`.failed`
/// ならOFF、`.downloading`/`.downloaded`ならON)をそのままトグルの見た目にしている ―
/// ダウンロード自体が`DownloadStore`の中で完結した状態機械のため、二重に状態を持つ必要がない。
///
/// ONにする(`.notDownloaded`/`.failed`から)と即座に`DownloadStore.startDownloadIfNeeded(for:)`
/// を呼ぶ。OFFにする(`.downloading`/`.downloaded`から)場合は「ダウンロード中や、ダウンロード後に
/// トグルをOffにしたらPromptしてYesなら消す」という要望通り、確認ダイアログを挟んでから
/// `DownloadStore.disableLocalSave(for:)`(ダウンロード中なら中断、完了済みならゴミ箱へ移動)を呼ぶ
/// ― キャンセルした場合は`state`が変わらないため、トグルは`get`の再評価で自動的にONへ戻る。
struct LocalSaveToggle: View {
    let video: VideoItem

    @ObservedObject private var downloadStore = DownloadStore.shared
    @State private var showsConfirmation = false
    @State private var errorMessage: String?

    private var state: DownloadStore.State { downloadStore.state(for: video) }

    private var isOn: Bool {
        switch state {
        case .downloading, .downloaded: return true
        case .notDownloaded, .failed: return false
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Toggle("ローカルに保存", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    if newValue {
                        downloadStore.startDownloadIfNeeded(for: video)
                    } else {
                        showsConfirmation = true
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            statusText
        }
        .confirmationDialog(
            "「\(video.title)」のローカル保存をオフにしますか?(保存済みのコピーがあれば削除します。OneDrive上の元動画は削除されません)",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button("オフにする", role: .destructive, action: disableLocalSave)
            Button("キャンセル", role: .cancel) {}
        }
        .alert(
            "削除できませんでした",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch state {
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView(value: progress)
                    .frame(width: 40)
                Text("ローカルに保存中…")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        case .downloaded:
            if let size = downloadStore.localFileSize(for: video) {
                Text(Self.sizeText(size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .notDownloaded, .failed:
            EmptyView()
        }
    }

    private func disableLocalSave() {
        Task {
            do {
                try await downloadStore.disableLocalSave(for: video)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
