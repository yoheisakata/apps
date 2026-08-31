import AVKit
import SwiftUI

/// `AVPlayerViewController`を`UIViewControllerRepresentable`で直接ラップしたもの
/// (myslideshow(Mac版)は`AVPlayerView`を`NSViewRepresentable`でラップしているが、
/// iOSにAppKitの対応物は無いためAVKitのiOS側API `AVPlayerViewController`を使う ―
/// mytube-ipadの`Views/NativeVideoPlayerView.swift`と同じ移植方針)。標準コントロールは
/// 出さない(`showsPlaybackControls = false`) ― スライドショーは自動連続再生が主目的で、
/// 一時停止/前後送りは`Views/SlideshowView.swift`側の自前オーバーレイ+タップ操作で行うため。
struct NativeVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
