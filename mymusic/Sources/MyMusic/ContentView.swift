import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var urlText = ""
    @State private var showingImport = false
    @AppStorage("isShuffled") private var isShuffled = false
    @State private var shuffleHistory: [Int] = []
    /// OneDrive の URL 取り直し中に別の曲が選ばれた場合、古い取得結果で再生を上書きしないための ID。
    @State private var playRequestID = UUID()

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

            if let notice = store.lastNotice {
                HStack {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        store.lastNotice = nil
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
        let track = store.tracks[index]
        guard track.oneDrive != nil else {
            player.load(track: track, index: index)
            return
        }
        // OneDrive の署名付き URL は保存したものが失効しているため、再生直前に取り直す。
        // 取得中に別の曲が選ばれた場合(playRequestID が変わる)は古い結果を捨てる。
        let requestID = UUID()
        playRequestID = requestID
        Task {
            let refreshed = await store.refreshedTrack(track)
            guard playRequestID == requestID else { return }
            guard let currentIndex = store.tracks.firstIndex(where: { $0.id == track.id }) else { return }
            player.load(track: refreshed, index: currentIndex)
        }
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
            TextField("YouTube / Suno / MusicCreator / MusicGPT / OneDrive 共有リンクを貼り付け", text: $urlText)
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
