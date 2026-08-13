import AVFoundation
import Combine
import IOKit.pwr_mgt

/// `AVPlayer` を薄くラップする。プレイリスト(次に何を再生するか)の中身は一切知らず、
/// 再生中の1本が最後まで終わったら `onFinished` を呼ぶだけに留める
/// (mymusic/Sources/MyMusic/PlayerEngine.swift と同じ設計方針)。
@MainActor
final class PlayerEngine: ObservableObject {
    let player = AVPlayer()
    private(set) var currentURL: URL?
    var onFinished: (() -> Void)?

    /// 再生開始に失敗した、または再生中にエラーで止まった場合に呼ばれる(日本語の
    /// エラーメッセージ付き)。`PlayerPaneView` がこれを受けてポップアップ(alert)を出す。
    var onError: ((String) -> Void)?

    /// 選択中の再生速度(0.5〜2.0倍)。動画を切り替えても保持する(YouTube と同じ挙動)。
    @Published private(set) var playbackRate: Float = 1.0

    private var itemEndObserver: NSObjectProtocol?
    private var itemFailedObserver: NSObjectProtocol?
    private var itemErrorLogObserver: NSObjectProtocol?
    private var rateCancellable: AnyCancellable?
    private var itemStatusCancellable: AnyCancellable?
    private var readyTimeoutTask: Task<Void, Never>?

    /// 再生中はディスプレイスリープ(≒画面が暗くなる/スクリーンセーバー)を抑止する。
    /// AVPlayerView はマウス/キーボード操作が無くても内部で自動的にこのアサーションを
    /// 取得してくれるわけではなく、フルスクリーン再生中は動画を見ているだけで数分操作が
    /// 無くなるため、OS 標準のアイドルスリープタイマーに引っかかって画面が暗くなっていた
    /// (ユーザー報告、2026-08-04)。`player.rate` の変化(既存の rateCancellable と同じ
    /// KVO 購読)に合わせて再生中だけ IOPMAssertion を確保し、一時停止/停止で確実に解放する。
    private var displaySleepAssertionID: IOPMAssertionID?

    init() {
        // AVPlayerView 標準コントロールの再生ボタンは、押されるたびに rate を無条件で 1.0 に
        // リセットしてしまう(NativeVideoPlayerView.swift 参照)。これを検知し、選択中の速度が
        // 1.0 以外なら即座に再適用することで、標準の一時停止/再開ボタンを使っても選んだ速度が
        // 保たれるようにする。
        rateCancellable = player.publisher(for: \.rate)
            .sink { [weak self] newRate in
                guard let self else { return }
                if newRate != 0 {
                    self.beginPreventingDisplaySleep()
                } else {
                    self.endPreventingDisplaySleep()
                }
                guard newRate != 0, self.playbackRate != 1.0, newRate != self.playbackRate else { return }
                self.player.rate = self.playbackRate
            }
    }

    private func beginPreventingDisplaySleep() {
        guard displaySleepAssertionID == nil else { return }
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MyTube is playing a video" as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            displaySleepAssertionID = assertionID
        }
    }

    private func endPreventingDisplaySleep() {
        guard let assertionID = displaySleepAssertionID else { return }
        IOPMAssertionRelease(assertionID)
        displaySleepAssertionID = nil
    }

    func load(url: URL, autoplay: Bool = true) {
        guard url != currentURL else { return }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        if let itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
        }
        if let itemErrorLogObserver {
            NotificationCenter.default.removeObserver(itemErrorLogObserver)
        }
        readyTimeoutTask?.cancel()
        let item = AVPlayerItem(url: url)
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onFinished?() }
        }
        // 再生開始後(バッファ中/再生中)にネットワーク切断・破損データ等で止まった場合。
        // `status == .failed`(下記)は再生を開始する前の失敗をカバーするのに対し、こちらは
        // 一度再生が始まった後の失敗をカバーする ― 両方無いとエラーを取りこぼすケースがある。
        itemFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let message = error?.localizedDescription ?? "不明なエラーで再生が中断されました"
            Task { @MainActor in self?.onError?(message) }
        }
        // コーデック非対応・ファイル破損・見つからない等、再生を開始できない失敗はここで拾う
        // (`.failed` への遷移は非同期に起きるため item ごとに Combine で購読し直す)。
        itemStatusCancellable = item.publisher(for: \.status)
            .sink { [weak self] status in
                guard status == .failed else { return }
                let message = item.error?.localizedDescription ?? "動画を再生できませんでした"
                self?.onError?(message)
            }
        // OneDriveの署名付きURL(`@content.downloadUrl`)が期限切れ・アクセス拒否になっている
        // 場合、サーバーはHTTPエラー(403等)をエラーページのボディ付きで返すことが多い。この
        // ケースでは`AVPlayerItem.status`が`.failed`へ遷移せず`.unknown`のまま止まり、
        // `.AVPlayerItemFailedToPlayToEndTime`(再生開始後の失敗)も一度も再生が始まらないため
        // 発火せず、**上記2つの経路のどちらにも引っかからずポップアップが一切出ない**
        // (2026-08-07、ユーザー報告で発覚 ― 「OneDrive系が全部再生できなくなってる」のに
        // エラーも出ないという不具合)。`AVPlayerItemNewErrorLogEntry`(HTTPレベルのエラーを
        // 含む`errorLog()`が更新されるたびに飛ぶ通知)を追加で購読し、こちらで拾う。
        itemErrorLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main
        ) { [weak self] _ in
            guard let event = item.errorLog()?.events.last else { return }
            let detail = event.errorComment ?? event.errorDomain
            let message = event.errorStatusCode != 0
                ? "動画の読み込みに失敗しました(HTTP \(event.errorStatusCode)): \(detail)"
                : "動画の読み込みに失敗しました: \(detail)"
            Task { @MainActor in self?.onError?(message) }
        }
        // 上記いずれにも引っかからず`.unknown`のまま止まる(サーバーがエラーログすら残さない
        // 応答をする等)最後の保険として、一定時間経っても`.readyToPlay`/`.failed`に進まなければ
        // タイムアウトとして通知する。`item`が既に別の動画に差し替えられていないか
        // (`player.currentItem === item`)を確認してから判定する。
        readyTimeoutTask = Task { [weak self, weak item] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self, let item, self.player.currentItem === item else { return }
            guard item.status == .unknown else { return }
            self.onError?("動画の読み込みがタイムアウトしました(共有リンクの期限切れの可能性があります)")
        }
        player.replaceCurrentItem(with: item)
        currentURL = url
        if autoplay {
            player.playImmediately(atRate: playbackRate)
        }
    }

    /// 再生速度を変更する。一時停止中に選んだ場合は値だけ覚えておき、実際の適用は
    /// 次に再生が始まったタイミング(上記 `rateCancellable` 経由)に任せる
    /// (`player.rate` に非ゼロ値を直接設定すると、一時停止中でも再生が始まってしまうため)。
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if player.timeControlStatus != .paused {
            player.rate = rate
        }
    }

    /// スペースキーでの再生/一時停止用。`player.pause()`/`player.play()` の代わりに
    /// `rate` を直接見て切り替えるのは、`player.play()` が常に rate を 1.0 にリセットして
    /// しまい選択中の再生速度(`playbackRate`)を無視してしまうため。
    func togglePlayPause() {
        if player.rate == 0 {
            player.rate = playbackRate
        } else {
            player.pause()
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        itemStatusCancellable = nil
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil
        if let itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
        }
        itemFailedObserver = nil
        if let itemErrorLogObserver {
            NotificationCenter.default.removeObserver(itemErrorLogObserver)
        }
        itemErrorLogObserver = nil
        endPreventingDisplaySleep()
    }

    deinit {
        if let displaySleepAssertionID {
            IOPMAssertionRelease(displaySleepAssertionID)
        }
    }
}
