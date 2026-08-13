import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var urlText = ""
    @State private var showingImport = false
    @AppStorage("isShuffled") private var isShuffled = false
    @State private var shuffleHistory: [Int] = []

    private var currentTrack: Track? {
        guard let idx = player.currentIndex, store.tracks.indices.contains(idx) else { return nil }
        return store.tracks[idx]
    }

    var body: some View {
        VStack(spacing: 12) {
            if store.ytdlpPath == nil || store.ffmpegPath == nil {
                Text("⚠️ yt-dlp / ffmpeg が見つかりません。YouTube リンクの追加には Homebrew でのインストールが必要です。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }
            if let error = store.lastError {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        store.lastError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                AddLinkField(urlText: $urlText, isResolving: store.resolvingCount > 0) {
                    store.addLink(urlText)
                    urlText = ""
                }
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .help("複数リンクをまとめてインポート")
            }

            PlayerControlsView(
                track: currentTrack,
                player: player,
                isShuffled: $isShuffled,
                onPrevious: playPrevious,
                onNext: playNext
            )

            Divider()

            PlaylistView(
                tracks: store.tracks,
                currentIndex: player.currentIndex,
                isPlaying: player.isPlaying,
                onSelect: { playTrack(at: $0) },
                onDelete: { store.remove(at: $0) },
                onMove: { store.move(from: $0, to: $1) }
            )
        }
        .padding()
        .onAppear {
            player.onTrackFinished = { playNext() }
        }
        .sheet(isPresented: $showingImport) {
            ImportLinksView(store: store)
        }
    }

    private func playTrack(at index: Int, recordHistory: Bool = true) {
        guard store.tracks.indices.contains(index) else { return }
        if recordHistory, isShuffled, let current = player.currentIndex, current != index {
            shuffleHistory.append(current)
        }
        player.load(track: store.tracks[index], index: index)
    }

    private func playNext() {
        guard !store.tracks.isEmpty else { return }
        if isShuffled {
            guard let random = randomIndexExcludingCurrent() else { return }
            playTrack(at: random)
        } else {
            guard let idx = player.currentIndex else { return }
            let next = idx + 1
            if store.tracks.indices.contains(next) {
                playTrack(at: next)
            } else {
                player.stop()
            }
        }
    }

    private func playPrevious() {
        if isShuffled {
            guard let last = shuffleHistory.popLast() else { return }
            playTrack(at: last, recordHistory: false)
        } else {
            guard let idx = player.currentIndex else { return }
            let prev = idx - 1
            if store.tracks.indices.contains(prev) {
                playTrack(at: prev)
            }
        }
    }

    private func randomIndexExcludingCurrent() -> Int? {
        let candidates = store.tracks.indices.filter { $0 != player.currentIndex }
        return candidates.randomElement() ?? store.tracks.indices.randomElement()
    }
}

/// URL 貼り付け用の入力欄。
private struct AddLinkField: View {
    @Binding var urlText: String
    var isResolving: Bool
    var onAdd: () -> Void

    var body: some View {
        HStack {
            TextField("YouTube / Suno / MusicCreator / MusicGPT の URL を貼り付け", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onAdd)
            Button(action: onAdd) {
                if isResolving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
