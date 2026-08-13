import SwiftUI

/// ウィンドウ最上部に常駐する再生バー(iTunes/Music.app のトップバー相当)。
/// サイドバー + 曲リストの横長レイアウトに合わせて、以前の縦積み(大きいアートワーク +
/// その下にシークバー)から横一列に組み替えてある。
struct PlayerControlsView: View {
    let track: Track?
    @ObservedObject var player: PlayerEngine
    @Binding var isShuffled: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void

    @State private var artwork: NSImage?
    @State private var isSeeking = false
    @State private var seekValue: Double = 0
    @State private var volume: Double = 1.0

    var body: some View {
        HStack(spacing: 14) {
            transportButtons

            artworkView
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // 再生バーは 40pt = Retina で 80px なので、行の small(96px)ではなく
                // medium(176px)を取ってくる。
                .task(id: track?.id) {
                    guard let track else { artwork = nil; return }
                    if let cached = ArtworkStore.shared.cached(for: track, size: .medium) {
                        artwork = cached
                    } else {
                        artwork = await ArtworkStore.shared.loadImage(for: track, size: .medium).image
                    }
                }

            nowPlaying
                .frame(minWidth: 160)

            volumeSlider
                .frame(width: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var transportButtons: some View {
        HStack(spacing: 14) {
            Button {
                isShuffled.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(isShuffled ? Color.accentColor : Color.secondary)
            }
            .help(isShuffled ? "シャッフル: オン" : "シャッフル: オフ")

            Group {
                Button(action: onPrevious) {
                    Image(systemName: "backward.end.fill")
                }
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                }
                Button(action: onNext) {
                    Image(systemName: "forward.end.fill")
                }
            }
            .disabled(track == nil)
        }
        .buttonStyle(.plain)
    }

    /// 曲名 + フォルダ階層(またはサイト名)+ シークバー。ウィンドウ幅の残りを全部使う。
    private var nowPlaying: some View {
        VStack(spacing: 1) {
            Text(track?.title ?? "再生中の曲はありません")
                .font(.subheadline)
                .lineLimit(1)
            if let track {
                Text(track.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack(spacing: 6) {
                Text(formatTime(isSeeking ? seekValue : player.currentTime))
                Slider(
                    value: Binding(
                        get: { isSeeking ? seekValue : player.currentTime },
                        set: { seekValue = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing { player.seek(to: seekValue) }
                    }
                )
                .disabled(track == nil)
                Text(formatTime(player.duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var volumeSlider: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.fill").font(.caption2)
            Slider(value: $volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill").font(.caption2)
        }
        .foregroundStyle(.secondary)
        .onChange(of: volume) { newValue in
            player.setVolume(Float(newValue))
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else if let urlString = track?.artworkURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholderArtwork
                }
            }
        } else {
            placeholderArtwork
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
