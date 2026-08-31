import AVFoundation
import SwiftUI

// アプリのバージョン。リリース時はここだけ更新する(mytube/mynetworth と同じ方式)。
let appVersion = "1.0.0"

@main
struct MyTubePadApp: App {
    init() {
        // Picture in Picture中(アプリがバックグラウンドへ回った状態)も音声・映像の再生を
        // 継続するための設定(2026-08-27追加、「最前面表示モード(PIP?)機能を追加してほしい」
        // という要望への対応)。`.playback`カテゴリはサイレントスイッチの状態に関わらず
        // 再生でき、バックグラウンド再生も許可する ― `project.yml`の
        // `UIBackgroundModes: [audio]`とセットで必要(どちらか片方だけでは、アプリを
        // 離れた瞬間にPiPが停止する)。
        // **`setActive(true)`をメインスレッドで直接呼ばない**(2026-08-28、実機で
        // 「... siveness if called on the main thread. Consider using the asynchronous
        // activate/deactivate API instead for calls from the main thread.」という警告と
        // 共にクラッシュした報告への対応)。`init()`はメインスレッドで呼ばれるが、
        // `setActive`は同期的でブロッキングしうるとAppleが警告している ―
        // `activate(options:completionHandler:)`という非同期版APIも存在するが、
        // 実際にはiOSでは`unavailable`(macOS専用)でビルドが通らなかったため、
        // 代わりにバックグラウンドキューへ`DispatchQueue.global().async`で逃がして
        // メインスレッドをブロックしないようにした。有効化の成否は無視してよい ―
        // 失敗してもストリーミング再生自体は続行できる(PiPでのバックグラウンド再生
        // 継続だけがベストエフォートになる)。
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback)
            try? session.setActive(true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
