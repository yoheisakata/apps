import SwiftUI

/// 右側の曲リスト。サイドバーで選んだ範囲(`ContentView.visibleTracks`)だけを表示し、
/// そのままの並びが再生キューになる。
struct PlaylistView: View {
    let tracks: [Track]
    let currentTrackID: UUID?
    let isPlaying: Bool
    /// 並び替えを許可するか(ライブラリ全体を素の並びで見ているときだけ ―
    /// 絞り込み中の行を動かしても、元の配列のどこへ挿すのかが決められないため)。
    let allowsReorder: Bool
    var emptyMessage: String
    var onSelect: (Track) -> Void
    var onDelete: ([Track]) -> Void
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        if tracks.isEmpty {
            VStack {
                Spacer()
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(tracks) { track in
                    PlaylistRow(
                        track: track,
                        isCurrent: track.id == currentTrackID,
                        isPlaying: isPlaying && track.id == currentTrackID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(track) }
                    // 削除は「MyMusic のライブラリ(playlist.json)から外す」だけで、
                    // OneDrive 上のファイルにも共有元にも一切触れない。標準の `.onDelete` は
                    // ラベルが「削除」固定で、OneDrive の曲だと「クラウドのファイルが消える」と
                    // 誤解されうるため(ユーザーからの問い合わせで判明)、`.swipeActions` で
                    // 文言を出し分けている。
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete([track])
                        } label: {
                            Label(track.oneDrive == nil ? "削除" : "外す", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        if track.oneDrive == nil {
                            Button("この曲を削除", role: .destructive) { onDelete([track]) }
                        } else {
                            Button("ライブラリから外す(OneDrive のファイルは消えません)", role: .destructive) {
                                onDelete([track])
                            }
                        }
                    }
                }
                .onMove(perform: allowsReorder ? onMove : nil)
            }
            .listStyle(.inset)
        }
    }
}

private struct PlaylistRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    /// OneDrive の曲のジャケット。表示された行のぶんだけ遅延取得する(`ArtworkStore`)。
    @State private var artwork: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(track.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        .task(id: track.id) {
            if let cached = ArtworkStore.shared.cached(for: track, size: .small) {
                artwork = cached
            } else {
                artwork = await ArtworkStore.shared.loadImage(for: track, size: .small).image
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else if let urlString = track.artworkURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
            Image(systemName: track.site == .oneDrive ? "music.note" : track.site.symbolName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
