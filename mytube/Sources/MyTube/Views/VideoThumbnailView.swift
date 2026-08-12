import AppKit
import SwiftUI

/// 動画1本ぶんのサムネイル(16:9、長さバッジ+ダウンロード状態バッジ付き)。
/// グリッド(`VideoCardView`)・一覧/ハイブリッド(`VideoTableView`)で共通して使う
/// (2026-08-05、`VideoCardView`にあった実装を切り出したもの)。`width`が`nil`なら親の幅
/// いっぱいに広がる(グリッドのセル用)、指定すればその幅に固定される(ハイブリッドの行用)。
struct VideoThumbnailView: View {
    let video: VideoItem
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = 10
    /// 右下の長さバッジを重ねて表示するか。ハイブリッド型のように幅が狭いサムネイルでは
    /// バッジがサムネイル本体と被って見づらくなるため、`VideoTableView`は`false`を渡し、
    /// 代わりに別列で長さを表示する(2026-08-05、「ハイブリッド時はサムネに時間が被っている」
    /// という指摘を受けて追加)。
    var showsDurationBadge: Bool = true

    @ObservedObject private var downloadStore = DownloadStore.shared
    @State private var image: NSImage?
    @State private var duration: TimeInterval?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // `thumbnail`(Image側)は`.aspectRatio(contentMode: .fill)`で元動画自身の比率
            // (16:9とは限らない)を使って理想サイズを報告する。これに外側から直接
            // `.aspectRatio(16/9, .fit)`を重ねると、`ScrollView`内の`LazyVGrid`/`LazyVStack`
            // (高さの提案がnilになりがちな環境)でセルごとに実際に確保される高さがブレるため、
            // `GeometryReader`で幅×高さを確定させてから`.clipped()`する。
            Group {
                if let width {
                    sizedBox.frame(width: width)
                } else {
                    sizedBox.frame(maxWidth: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .topLeading) {
                if video.isRemote {
                    DownloadBadge(state: downloadStore.state(for: video), fileSize: downloadStore.localFileSize(for: video))
                }
            }

            if showsDurationBadge, let duration {
                Text(Self.formatDuration(duration))
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
        .task(id: video.id) {
            if let cached = ThumbnailStore.shared.cachedImage(for: video) {
                image = cached
                duration = ThumbnailStore.shared.cachedDuration(for: video)
                return
            }
            let result = await ThumbnailStore.shared.load(for: video)
            image = result.image
            duration = result.duration
        }
    }

    private var sizedBox: some View {
        GeometryReader { proxy in
            thumbnail
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.22))
                .overlay(
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                )
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// リモート動画のサムネイル左上に出す、ローカル保存状態のバッジ。
/// `.notDownloaded`/`.failed`は何も表示しない(`PlayerPaneView`の`DownloadStatusLabel`と同じ方針)。
struct DownloadBadge: View {
    let state: DownloadStore.State
    /// ダウンロード済みのローカルコピーの実際のファイルサイズ(2026-08-05追加、「ローカルにDLした
    /// サイズを各ビデオに表示してほしい」という要望への対応)。`nil`ならサイズ無しで
    /// チェックマークだけ表示する(`DownloadStore.localFileSize(for:)`が`stat`に失敗した場合の保険)。
    var fileSize: Int64? = nil

    var body: some View {
        switch state {
        case .notDownloaded, .failed:
            EmptyView()
        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.75))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)
        case .downloaded:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let fileSize {
                    Text(Self.sizeText(fileSize))
                }
            }
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.75))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
        }
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
