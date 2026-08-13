import AVFoundation

@MainActor
final class PlayerEngine: ObservableObject {
    @Published var isPlaying = false
    /// 再生中の曲。**プレイリスト内の位置(index)ではなく曲そのものを持つ** ―
    /// サイドバーでフォルダを選び替えるとキューの中身も並びも変わるため、index では
    /// 「今どれを鳴らしているか」を安定して表せない(次の曲の決定は `ContentView` の責務)。
    @Published var currentTrack: Track?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    /// 曲が最後まで再生し終わったときに呼ばれる。ContentView 側でプレイリストの次曲を計算して
    /// `load(track:index:)` を呼び直す(PlayerEngine 自体はプレイリストの中身を知らない)。
    var onTrackFinished: (() -> Void)?

    private let player = AVPlayer()
    private var itemEndObserver: NSObjectProtocol?

    init() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds
                if let d = self.player.currentItem?.duration, d.isNumeric {
                    self.duration = d.seconds
                }
            }
        }
    }

    func load(track: Track, autoplay: Bool = true) {
        guard let url = URL(string: track.audioURL) else { return }
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        let item = AVPlayerItem(url: url)
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onTrackFinished?() }
        }
        player.replaceCurrentItem(with: item)
        currentTrack = track
        currentTime = 0
        duration = 0
        if autoplay {
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func setVolume(_ value: Float) {
        player.volume = value
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTrack = nil
        currentTime = 0
        duration = 0
    }
}
