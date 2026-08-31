import AppKit
import SwiftUI

/// PIPモード(`PlaybackMode.pip`)専用の、小さな常時最前面(他アプリの上にも出る)浮動パネル。
/// **メインウィンドウ(ホーム画面)はPIP再生中も裏でそのまま表示され続ける** ― `.windowed`/
/// `.fullScreen`のようにメインウィンドウの中身を`SlideshowView`へ差し替えるのではなく、
/// `SlideshowView`をこのパネル専用の別ウィンドウへホストする(2026-08-30、「スライドショーには
/// 3つのモードがほしい: ウィンドウ内/全画面/PIP」という要望への対応。「PIP」の実体は macOS
/// ネイティブの動画専用Picture-in-Picture(AVKit)ではなく自前の浮動ウィンドウ ― 写真も扱う
/// このアプリではAVKitのPIPは動画にしか使えず要件に合わないため、ユーザーに確認のうえ
/// 「自前の小さい常時最前面ウィンドウ」を選んだ)。
final class PIPWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    /// 既にPIPパネルが開いていれば前面に出すだけ、無ければ新規に作って`items`を再生する。
    func show(items: [MediaItem], timeLimitMinutes: Int?, onExit: @escaping () -> Void) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 320, height: 240)
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // タイトルバーを透明化し文字も隠すことで、見た目上はクロームレスな浮動ウィンドウに
        // する(トラフィックライト[閉じるボタン]だけは残す ― ドラッグでの移動・自前の✕
        // ボタンに加えてネイティブな閉じ方も用意しておく)。
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.isMovableByWindowBackground = true
        newPanel.minSize = NSSize(width: 200, height: 150)
        // 他アプリの上にも常に表示され、Spaces切り替えやフルスクリーンアプリの上へも
        // 追随する(通常ウィンドウはSpace固有・フルスクリーン中は隠れるため、この
        // 2つのcollectionBehaviorが「常時最前面」の要件に必須)。
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.delegate = self

        let slideshow = SlideshowView(
            items: items,
            playbackMode: .pip,
            timeLimitMinutes: timeLimitMinutes,
            onExit: { [weak self] in
                self?.close()
                onExit()
            }
        )
        newPanel.contentView = NSHostingView(rootView: slideshow)
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)
        panel = newPanel
    }

    /// パネルを閉じる(自前の✕ボタン/escキー、`SlideshowView`の`onExit`経由)。
    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// パネル自身のネイティブ閉じるボタンで閉じられた場合もここへ来る ― `SlideshowView`
    /// 自体の後始末(`onDisappear`でのタスクキャンセル等)はウィンドウが閉じてビューが
    /// 破棄されることで自動的に走るため、ここでは参照を手放すだけでよい。
    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
