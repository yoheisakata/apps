import SwiftUI

struct PlaylistView: View {
    let tracks: [Track]
    let currentIndex: Int?
    let isPlaying: Bool
    var onSelect: (Int) -> Void
    var onDelete: (IndexSet) -> Void
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        if tracks.isEmpty {
            VStack {
                Spacer()
                Text("プレイリストは空です。上の欄に URL を貼り付けて追加してください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
        } else {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    PlaylistRow(
                        track: track,
                        isCurrent: index == currentIndex,
                        isPlaying: isPlaying && index == currentIndex
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(index) }
                }
                .onDelete(perform: onDelete)
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
        }
    }
}

private struct PlaylistRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(track.site.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = track.artworkURL, let url = URL(string: urlString) {
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
            Image(systemName: "music.note").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
