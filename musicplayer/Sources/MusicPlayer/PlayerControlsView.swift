import SwiftUI

struct PlayerControlsView: View {
    let track: Track?
    @ObservedObject var player: PlayerEngine
    @Binding var isShuffled: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void

    @State private var isSeeking = false
    @State private var seekValue: Double = 0
    @State private var volume: Double = 1.0

    var body: some View {
        VStack(spacing: 10) {
            artwork
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 3)

            VStack(spacing: 2) {
                Text(track?.title ?? "再生中の曲はありません")
                    .font(.headline)
                    .lineLimit(1)
                if let site = track?.site {
                    Label(site.label, systemImage: site.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 2) {
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
                HStack {
                    Text(formatTime(isSeeking ? seekValue : player.currentTime))
                    Spacer()
                    Text(formatTime(player.duration))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
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
                            .font(.system(size: 40))
                    }
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill")
                    }
                }
                .disabled(track == nil)
            }
            .buttonStyle(.plain)

            HStack {
                Image(systemName: "speaker.fill").font(.caption2)
                Slider(value: $volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .onChange(of: volume) { newValue in
                player.setVolume(Float(newValue))
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let urlString = track?.artworkURL, let url = URL(string: urlString) {
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
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15))
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
