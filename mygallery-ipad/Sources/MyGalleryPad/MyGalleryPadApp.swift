import AVFoundation
import SwiftUI

// アプリのバージョン。リリース時はここだけ更新する(mytube-ipad/myslideshow-ipadと同じ方式)。
let appVersion = "1.0.0"

@main
struct MyGalleryPadApp: App {
    init() {
        // サイレントスイッチがオンでも動画の音声を再生するための設定(既定の`.soloAmbient`は
        // サイレントスイッチで無音化される)。mytube-ipad/myslideshow-ipadの`init()`と
        // 同じ理由で`setActive(true)`はメインスレッドで直接呼ばない ― `init()`は
        // メインスレッドで呼ばれるが、同期版`setActive`はブロッキングしうるとAppleが
        // 警告しており、実機で警告と共にクラッシュした報告(mytube-ipad, 2026-08-28)への
        // 対応を踏襲している。非同期版`activate(options:completionHandler:)`はiOSでは
        // `unavailable`のため使えない。
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
