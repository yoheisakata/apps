import AVKit
import SwiftUI

/// `AVKit.VideoPlayer`(SwiftUI)ではなく`AVPlayerViewController`を直接
/// `UIViewControllerRepresentable`でラップする(2026-08-27追加、「最前面表示モード(PIP?)
/// 機能を追加してほしい」という要望への対応)。`VideoPlayer`はPicture in Picture関連の
/// プロパティ(`allowsPictureInPicturePlayback`/`canStartPictureInPictureAutomaticallyFromInline`)
/// を明示的に設定する手段を公開していないため、確実にPiPを有効化・自動開始させるには
/// AVKitへ薄く橋渡しする必要があった(mytube Mac版が`VideoPlayer`ではなく`AVPlayerView`を
/// 直接ラップしているのと同じ「無い機能はAVKit/AppKitへ橋渡しする」方針)。
struct NativeVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        // アプリを離れた瞬間(ホームに戻る/他アプリへ切り替える)に自動でPiPへ移行する ―
        // PiPボタンを明示的に押さなくても「最前面表示」になる、という要望に沿うため。
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
