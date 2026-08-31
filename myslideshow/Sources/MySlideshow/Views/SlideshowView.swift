import AppKit
import SwiftUI

/// フルスクリーンで写真・動画を自動連続再生する画面。写真は`Settings.photoDurationSeconds`
/// 秒だけ表示して次へ進み、動画は最後まで再生してから次へ進む(操作不要でテレビのように
/// 流しっぱなしにする、という要望に対応)。マウスを動かすと下部に一時停止/前後送り/終了の
/// オーバーレイが3秒だけ現れる ― 子どもが誤って操作しないよう、常時は何も出さない。
///
/// **時間制限**(`timeLimitMinutes`、2026-08-29追加、「スライドショーの時間制限を作りたい」
/// という要望への対応) — 非nilなら、開始からその分数が経過した時点で自動的に`onExit()`を
/// 呼んで終了する(`scheduleTimeLimitIfNeeded()`)。**ハイライト再生機能は同日中に
/// 「削除」の要望を受けて撤去済み**(動画を3分割して要点だけ再生する機能があったが、
/// `Core/PlayerEngine.swift`の`playSegment`ごと削除し、動画は常に通しで最後まで
/// 再生する元の挙動に戻した)。
struct SlideshowView: View {
    let items: [MediaItem]
    /// 表示モード(2026-08-30追加、「ウィンドウ内/全画面/PIP」の3モード要望への対応)。
    /// `.fullScreen`/`.windowed`はメインウィンドウの中身として表示され、ここでの
    /// 挙動の違いは`applyWindowModeIfNeeded()`/`restoreWindowModeIfNeeded()`が
    /// メインウィンドウを直接操作する形だけ。`.pip`は`Core/PIPWindowController.swift`が
    /// 別の浮動パネルへホストするため、ここでのウィンドウ操作は不要(何もしない)。
    let playbackMode: PlaybackMode
    /// スライドショー全体の time limit(分)。`nil`なら無制限。
    let timeLimitMinutes: Int?
    let onExit: () -> Void

    @State private var currentIndex = 0
    @State private var isPaused = false
    @State private var currentImage: NSImage?
    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var photoAdvanceTask: Task<Void, Never>?
    @State private var timeLimitTask: Task<Void, Never>?
    @State private var loadToken = UUID()
    @State private var keyMonitor: Any?
    @StateObject private var engine = PlayerEngine()

    private var current: MediaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current {
                switch current.kind {
                case .photo:
                    if let currentImage {
                        Image(nsImage: currentImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .id(current.id)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                    }
                case .video:
                    NativeVideoPlayerView(player: engine.player)
                        .id(current.id)
                }
            } else {
                Text("表示できる写真・動画がありません")
                    .foregroundStyle(.white)
            }

            if let current, let capturedDate = current.capturedDate {
                dateLabel(for: capturedDate)
            }

            if showsControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
        .contentShape(Rectangle())
        .onContinuousHover { _ in revealControls() }
        .onAppear {
            setupEngineCallbacks()
            installKeyMonitor()
            applyWindowModeIfNeeded()
            revealControls()
            loadCurrent()
            scheduleTimeLimitIfNeeded()
        }
        .onChange(of: currentIndex) { _ in loadCurrent() }
        .onDisappear {
            engine.stop()
            photoAdvanceTask?.cancel()
            hideControlsTask?.cancel()
            timeLimitTask?.cancel()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }

    private var controlsOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 24) {
                Button(action: goPrevious) {
                    Image(systemName: "backward.fill")
                }
                Button(action: togglePause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                }
                Button(action: goNext) {
                    Image(systemName: "forward.fill")
                }
                Spacer()
                if !items.isEmpty {
                    Text("\(currentIndex + 1) / \(items.count)")
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
                Button(action: exit) {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.title2)
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .padding(24)
        }
    }

    /// 右下に常時(操作オーバーレイと違い、マウスを動かさなくても)表示する撮影日ラベル。
    /// `MediaItem.capturedDate`(ファイル名から推測、`Core/FilenameDateParser.swift`)が
    /// 取れた写真・動画だけに出す ― 分からないものは何も表示しない。
    private func dateLabel(for date: Date) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(Self.dateFormatter.string(from: date))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .padding(16)
        .allowsHitTesting(false)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    // MARK: - 送り

    private func loadCurrent() {
        photoAdvanceTask?.cancel()
        engine.stop()
        currentImage = nil
        loadToken = UUID()
        guard let current else { return }

        switch current.kind {
        case .photo:
            let token = loadToken
            Task {
                let image = await ImageLoader.shared.image(for: current)
                guard token == loadToken else { return }
                currentImage = image
                schedulePhotoAdvance()
            }
            ImageLoader.shared.prefetch(upcoming())
        case .video:
            engine.load(url: current.downloadURL)
        }
    }

    private func upcoming(count: Int = 3) -> [MediaItem] {
        guard !items.isEmpty else { return [] }
        return (1...count).map { offset in
            items[(currentIndex + offset) % items.count]
        }
    }

    private func schedulePhotoAdvance() {
        guard !isPaused else { return }
        let duration = Settings.photoDurationSeconds
        photoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            goNext()
        }
    }

    private func goNext() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex + 1) % items.count
    }

    private func goPrevious() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + items.count) % items.count
    }

    private func togglePause() {
        isPaused.toggle()
        guard let current else { return }
        switch current.kind {
        case .video:
            engine.togglePlayPause()
        case .photo:
            if isPaused {
                photoAdvanceTask?.cancel()
            } else {
                schedulePhotoAdvance()
            }
        }
    }

    private func setupEngineCallbacks() {
        engine.onFinished = {
            if !isPaused { goNext() }
        }
        engine.onError = { _ in
            // 再生できない動画(コーデック非対応・OneDriveの署名付きURL期限切れ等)は
            // 止まらず次へ進む ― 子どもが操作できない前提の画面のため、エラーを見せるより
            // 流し続ける方を優先する。
            goNext()
        }
    }

    private func exit() {
        restoreWindowModeIfNeeded()
        onExit()
    }

    // MARK: - 時間制限

    /// `timeLimitMinutes`が設定されていれば、その分数が経過した時点で自動的に終了する。
    private func scheduleTimeLimitIfNeeded() {
        guard let minutes = timeLimitMinutes, minutes > 0 else { return }
        let seconds = Double(minutes) * 60
        timeLimitTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            exit()
        }
    }

    // MARK: - コントロールの自動表示/非表示

    private func revealControls() {
        showsControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            showsControls = false
        }
    }

    // MARK: - キーボード操作

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 49: // space
                togglePause()
                return nil
            case 123: // left arrow
                goPrevious()
                return nil
            case 124: // right arrow
                goNext()
                return nil
            case 53: // escape
                exit()
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - ウィンドウモード

    /// 既定の「大きめリサイズ可能ウィンドウ」サイズ(`.windowed`モード)。
    private static let windowedSize = NSSize(width: 960, height: 640)

    /// 表示開始時、モードに応じてメインウィンドウを調整する。`.pip`はメインウィンドウでは
    /// なく`PIPWindowController`が用意した専用パネルへホストされるため何もしない。
    private func applyWindowModeIfNeeded() {
        guard playbackMode != .pip, let window = NSApplication.shared.keyWindow else { return }
        switch playbackMode {
        case .fullScreen:
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        case .windowed:
            // ホーム画面は`ContentView`が固定420×560でリサイズ不可にしているため、
            // ここで明示的にリサイズ可能へ戻したうえで大きめのサイズへ広げる
            // (`ContentView`のホーム画面側`.frame(width:420,height:560)`が再度
            // 効くのはホーム画面へ戻ったとき ― `restoreWindowModeIfNeeded`は
            // 何もせずSwiftUI側の固定フレームに任せる)。
            window.styleMask.insert(.resizable)
            window.setContentSize(Self.windowedSize)
            window.center()
        case .pip:
            break
        }
    }

    /// 終了時、モードに応じてメインウィンドウを元に戻す。`.windowed`はホーム画面の
    /// `.frame(width:420,height:560)`(固定)が再表示された瞬間にSwiftUI側で自動的に
    /// リサイズ不可・小サイズへ戻るため、ここでは明示的な後始末は不要。
    private func restoreWindowModeIfNeeded() {
        guard playbackMode == .fullScreen, let window = NSApplication.shared.keyWindow,
              window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }
}
