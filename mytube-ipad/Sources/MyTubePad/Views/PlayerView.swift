import AVKit
import SwiftUI

/// フルスクリーン再生画面。`DownloadStore.shared.playableURL(for:)`が返すURL(ダウンロード
/// 済みならローカルファイル、そうでなければ`video.downloadURL`=tempauth署名付きの直リンク)を
/// `AVPlayer`に渡す(2026-08-27、`DownloadStore`追加に伴い`video.downloadURL`直渡しから
/// 変更 ― 下記参照)。署名の期限切れ(実測1時間程度)で未ダウンロードの動画の再生が
/// 失敗した場合は閉じてグリッドのプルダウン更新で再スキャンし、開き直せばよい。
///
/// **自動再生(2026-08-27追加、「次の動画に自動で進むようにしてほしい」という要望への
/// 対応)**: `queue`(タップした時点で`SourceGridView`に表示されていた一覧 ―
/// フォルダタブ・タグフィルター適用後のもの、`ContentView`経由でそのまま渡される)の中で
/// `video`が何番目かを`currentIndex`として起動し、`.AVPlayerItemDidPlayToEndTime`通知を
/// 監視して最後まで再生し終えるたびに`currentIndex`を進める。`queue`の最後まで到達したら
/// 自動的に`onClose()`を呼んで画面を閉じる(mytube Mac版の`PlayerEngine.onFinished`+
/// `PlayerPaneView.setupAutoplayNext()`と同じ発想だが、こちらはトグルで無効化する手段は
/// 持たない ― mytube-ipadはMVPとしての単純さを優先しているため常時オン)。
///
/// **Picture in Picture(2026-08-27追加、「最前面表示モード(PIP?)機能を追加してほしい」
/// という要望への対応)**: `VideoPlayer`(SwiftUI)ではなく`Views/NativeVideoPlayerView.swift`
/// (`AVPlayerViewController`を直接ラップ)を使う ― PiPの有効化・自動開始プロパティは
/// `VideoPlayer`から設定できないため。`canStartPictureInPictureAutomaticallyFromInline`を
/// trueにしているので、ユーザーがホームに戻る/他アプリへ切り替えるだけで自動的に
/// フローティングのPiPウィンドウへ移行する(iOS標準のシステムPiP ― 他アプリの上にも
/// 常に最前面で表示される)。バックグラウンドでも音声・映像を継続するため
/// `MyTubePadApp.init()`で`AVAudioSession`のカテゴリを`.playback`に設定し、
/// `project.yml`の`UIBackgroundModes`に`audio`を追加している(この2つが無いと、
/// アプリを離れた瞬間にPiPが停止する)。
struct PlayerView: View {
    let queue: [VideoItem]
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var player = AVPlayer()
    @State private var endObserver: NSObjectProtocol?

    init(video: VideoItem, queue: [VideoItem], onClose: @escaping () -> Void) {
        // `queue`に`video`自身が含まれない呼び出し方をされても再生自体は必ずできるように、
        // 空/未含有の場合は`[video]`1件だけのキューへフォールバックする。
        let resolvedQueue = queue.contains(where: { $0.id == video.id }) ? queue : [video]
        self.queue = resolvedQueue
        self.onClose = onClose
        _currentIndex = State(initialValue: resolvedQueue.firstIndex(where: { $0.id == video.id }) ?? 0)
    }

    private var currentVideo: VideoItem { queue[currentIndex] }
    private var hasNext: Bool { currentIndex + 1 < queue.count }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NativeVideoPlayerView(player: player)
                .ignoresSafeArea()
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    load(currentVideo)
                }
                .onChange(of: currentIndex) { _, _ in
                    load(currentVideo)
                }
                .onDisappear {
                    player.pause()
                    UIApplication.shared.isIdleTimerDisabled = false
                    removeEndObserver()
                }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
        .background(Color.black)
    }

    private func load(_ video: VideoItem) {
        removeEndObserver()
        // ダウンロード済みならローカルファイルを、そうでなければ`video.downloadURL`
        // (tempauth署名付きの直リンク)をストリーミング再生する(2026-08-27追加、
        // 「Local DL機能追加してほしい」という要望への対応)。
        let item = AVPlayerItem(url: DownloadStore.shared.playableURL(for: video))
        player.replaceCurrentItem(with: item)
        player.play()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in
            advanceToNext()
        }
    }

    private func advanceToNext() {
        guard hasNext else {
            onClose()
            return
        }
        currentIndex += 1
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}
