import AVKit
import SwiftUI

/// `AVPlayerViewController`を`UIViewControllerRepresentable`で直接ラップしたもの
/// (myslideshow-ipad/mytube-ipadと同じ移植方針 ― Mac版は`AVPlayerView`を
/// `NSViewRepresentable`でラップしているが、iOSにAppKitの対応物は無いためAVKitの
/// iOS側API `AVPlayerViewController`を使う)。
///
/// **`showsControls`を引数化した(このアプリ独自の変更)**: myslideshow-ipadは
/// スライドショー専用で常に`false`(標準コントロールは出さず、自前のオーバーレイ+
/// タップ操作だけ)だったが、MyGallery Padは手動ビューア(`Views/ViewerView.swift`)でも
/// 動画を再生する ― こちらは標準の再生バー(シークバー・音量等)をそのまま活かしたい
/// ため`true`で使う。スライドショー(`Views/SlideshowView.swift`)は従来通り`false`。
struct NativeVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsControls: Bool = false

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.showsPlaybackControls = showsControls
    }
}
