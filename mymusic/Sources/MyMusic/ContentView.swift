import SwiftUI

/// トップの再生バー + 左のライブラリツリー + 右の曲リスト、という3分割
/// (iTunes/Music.app や mytube と同じ構成)。
struct ContentView: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var urlText = ""
    @State private var searchText = ""
    @State private var showingImport = false
    @State private var selection: LibrarySelection = .all
    @AppStorage("isShuffled") private var isShuffled = false
    /// シャッフルの「前へ」用の履歴。キュー(サイドバーの選択)が変わっても意味を保てるよう、
    /// index ではなく `Track.id` を積む。
    @State private var shuffleHistory: [UUID] = []
    /// OneDrive の URL 取り直し中に別の曲が選ばれた場合、古い取得結果で再生を上書きしないための ID。
    @State private var playRequestID = UUID()

    /// サイドバーの選択 + 検索欄で絞り込んだ曲。この並びがそのまま再生キューになる。
    private var visibleTracks: [Track] {
        let scoped = store.tracks.filter { selection.matches($0) }
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return scoped }
        return scoped.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
                || $0.folderPath.joined(separator: "/").localizedCaseInsensitiveContains(keyword)
        }
    }

    private var isUnfiltered: Bool {
        selection == .all && searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerControlsView(
                track: player.currentTrack,
                player: player,
                isShuffled: $isShuffled,
                onPrevious: playPrevious,
                onNext: playNext
            )
            Divider()

            HStack(spacing: 0) {
                LibrarySidebarView(
                    allCount: store.tracks.count,
                    linkCount: store.tracks.filter { $0.oneDrive == nil }.count,
                    sources: store.oneDriveSources,
                    tracks: store.tracks,
                    selection: $selection,
                    onRescan: { store.addOneDriveShare($0) },
                    onRemoveSource: removeSource
                )
                .frame(width: 220)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                VStack(spacing: 8) {
                    banners
                    inputRow
                    PlaylistView(
                        tracks: visibleTracks,
                        currentTrackID: player.currentTrack?.id,
                        isPlaying: player.isPlaying,
                        allowsReorder: isUnfiltered,
                        emptyMessage: emptyMessage,
                        onSelect: { play($0) },
                        onDelete: { store.remove(tracks: $0) },
                        onMove: { store.move(from: $0, to: $1) }
                    )
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
            }
        }
        // `onTrackFinished` は「次に何を鳴らすか」を `visibleTracks`(= サイドバーの選択 +
        // 検索欄)から決めるため、そのもとになる状態が変わるたびにクロージャを作り直す
        // ― onAppear で1度だけ渡すと、View 構造体の古いコピーを捕まえたまま、最初に
        // 選んでいたフォルダのキューで自動送りし続けることになる(mytube で踏んだのと同じ罠)。
        .onAppear { setupAutoplay() }
        .onChange(of: selection) { _ in setupAutoplay() }
        .onChange(of: searchText) { _ in setupAutoplay() }
        .onChange(of: isShuffled) { _ in setupAutoplay() }
        .onChange(of: store.tracks.count) { _ in setupAutoplay() }
        .sheet(isPresented: $showingImport) {
            ImportLinksView(store: store)
        }
    }

    private var emptyMessage: String {
        if store.tracks.isEmpty {
            return "ライブラリは空です。上の欄に曲のリンクや OneDrive の共有リンクを貼り付けて追加してください。"
        }
        return "この場所に表示できる曲はありません。"
    }

    @ViewBuilder
    private var banners: some View {
        if store.ytdlpPath == nil || store.ffmpegPath == nil {
            banner(text: "⚠️ yt-dlp / ffmpeg が見つかりません。YouTube リンクの追加には Homebrew でのインストールが必要です。",
                   color: .orange, onDismiss: nil)
        }
        if let error = store.lastError {
            banner(text: error, color: .red) { store.lastError = nil }
        }
        if let notice = store.lastNotice {
            banner(text: notice, color: .secondary) { store.lastNotice = nil }
        }
    }

    private func banner(text: String, color: Color, onDismiss: (() -> Void)?) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(2)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
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

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("曲名で検索", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 180)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - 再生

    private func setupAutoplay() {
        player.onTrackFinished = { playNext() }
    }

    private func play(_ track: Track, recordHistory: Bool = true) {
        if recordHistory, isShuffled, let current = player.currentTrack, current.id != track.id {
            shuffleHistory.append(current.id)
        }
        guard track.oneDrive != nil else {
            player.load(track: track)
            return
        }
        // OneDrive の署名付き URL は保存したものが失効しているため、再生直前に取り直す。
        // 取得中に別の曲が選ばれた場合(playRequestID が変わる)は古い結果を捨てる。
        let requestID = UUID()
        playRequestID = requestID
        Task {
            let refreshed = await store.refreshedTrack(track)
            guard playRequestID == requestID else { return }
            player.load(track: refreshed)
        }
    }

    private func playNext() {
        let queue = visibleTracks
        guard !queue.isEmpty else { return }
        if isShuffled {
            let candidates = queue.filter { $0.id != player.currentTrack?.id }
            guard let next = candidates.randomElement() ?? queue.randomElement() else { return }
            play(next)
        } else {
            guard let current = player.currentTrack,
                  let index = queue.firstIndex(where: { $0.id == current.id })
            else {
                // キューに無い曲を再生中(フォルダを選び替えた等)なら先頭から。
                play(queue[0])
                return
            }
            let next = index + 1
            if queue.indices.contains(next) {
                play(queue[next])
            } else {
                player.stop()
            }
        }
    }

    private func playPrevious() {
        let queue = visibleTracks
        if isShuffled {
            guard let lastID = shuffleHistory.popLast(),
                  let previous = queue.first(where: { $0.id == lastID }) ?? store.tracks.first(where: { $0.id == lastID })
            else { return }
            play(previous, recordHistory: false)
        } else {
            guard let current = player.currentTrack,
                  let index = queue.firstIndex(where: { $0.id == current.id }),
                  queue.indices.contains(index - 1)
            else { return }
            play(queue[index - 1])
        }
    }

    private func removeSource(_ shareURL: String) {
        store.removeOneDriveSource(shareURL)
        if case .oneDriveFolder(let selected, _) = selection, selected == shareURL {
            selection = .all
        }
    }
}

/// URL 貼り付け用の入力欄。
private struct AddLinkField: View {
    @Binding var urlText: String
    var isResolving: Bool
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
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
