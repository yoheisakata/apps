import AVFoundation
import Combine

/// `AVPlayer`の薄いラッパー。再生キューの中身は一切知らず、1本の再生と`onFinished`/`onError`
/// コールバックだけを持つ(mytubeの`Core/PlayerEngine.swift`と同じ設計方針)。
/// **ハイライト再生(区間だけのシーク再生)は2026-08-29に機能ごと削除したため、
/// このファイルもそれ専用だった`playSegment`/`finishPendingSegment`等を撤去し、
/// 単純な通し再生だけの元の形に戻した。**
@MainActor
final class PlayerEngine: ObservableObject {
    let player = AVPlayer()
    var onFinished: (() -> Void)?
    var onError: ((String) -> Void)?

    private var itemEndObserver: NSObjectProtocol?
    private var itemFailedObserver: NSObjectProtocol?
    private var itemStatusCancellable: AnyCancellable?

    func load(url: URL) {
        removeObservers()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.onFinished?()
        }
        itemFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            self?.onError?(error ?? "再生エラー")
        }
        itemStatusCancellable = item.publisher(for: \.status).sink { [weak self] status in
            guard status == .failed else { return }
            self?.onError?(item.error?.localizedDescription ?? "再生できませんでした")
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeObservers()
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    private func removeObservers() {
        if let itemEndObserver { NotificationCenter.default.removeObserver(itemEndObserver) }
        if let itemFailedObserver { NotificationCenter.default.removeObserver(itemFailedObserver) }
        itemEndObserver = nil
        itemFailedObserver = nil
        itemStatusCancellable = nil
    }

    deinit {
        if let itemEndObserver { NotificationCenter.default.removeObserver(itemEndObserver) }
        if let itemFailedObserver { NotificationCenter.default.removeObserver(itemFailedObserver) }
    }
}
