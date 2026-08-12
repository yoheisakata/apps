import AVKit
import SwiftUI

/// `AVKit.VideoPlayer`(SwiftUI 版、`_AVKit_SwiftUI.framework` 経由)ではなく、
/// AppKit の `AVPlayerView` を直接ラップする。
///
/// 理由: `VideoPlayer` は `AVPlayerView` の薄いラッパーだが、フルスクリーン切り替えボタンの
/// 表示可否(`showsFullScreenToggleButton`、既定値 false)を設定する手段を公開していない。
/// `AVPlayerView` を直接使えばこのプロパティを true にするだけで、ボタンの表示から
/// 実際のフルスクリーン遷移(専用ウィンドウでの全画面表示)まで AVKit 側がすべて処理してくれる
/// (こちら側で `NSWindow` のフルスクリーン制御を書く必要はない)。
struct NativeVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
