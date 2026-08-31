import AVFoundation
import SwiftUI

// アプリのバージョン。リリース時はここだけ更新する(mytube-ipad/myslideshow(Mac版)と同じ方式)。
let appVersion = "1.0.0"

@main
struct MySlideshowPadApp: App {
    init() {
        // サイレントスイッチがオンでも動画の音声を再生するための設定(既定の`.soloAmbient`は
        // サイレントスイッチで無音化される)。mytube-ipadの`MyTubePadApp.init()`と同じ理由で
        // `setActive(true)`はメインスレッドで直接呼ばない ― `init()`はメインスレッドで
        // 呼ばれるが、同期版`setActive`はブロッキングしうるとAppleが警告しており、実機で
        // 警告と共にクラッシュした報告(mytube-ipad, 2026-08-28)への対応を踏襲している。
        // 非同期版`activate(options:completionHandler:)`はiOSでは`unavailable`のため使えない。
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
