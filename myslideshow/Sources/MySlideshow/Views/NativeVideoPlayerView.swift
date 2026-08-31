import AVKit
import SwiftUI

/// `AVPlayerView`(AppKit)を`NSViewRepresentable`で直接ラップしたもの。標準コントロールは
/// 出さない(`controlsStyle = .none`) ― スライドショーは自動連続再生が主目的で、一時停止/
/// 前後送りは`Views/SlideshowView.swift`側の自前オーバーレイ+キーボード操作で行うため。
struct NativeVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
