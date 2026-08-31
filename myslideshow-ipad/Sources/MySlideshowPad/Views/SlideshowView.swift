import SwiftUI

/// フルスクリーンで写真・動画を自動連続再生する画面。写真は`Settings.photoDurationSeconds`
/// 秒だけ表示して次へ進み、動画は最後まで再生してから次へ進む(操作不要でテレビのように
/// 流しっぱなしにする)。myslideshow(Mac版)の同名ファイルから移植 ―
///
/// - **ウィンドウモード(`playbackMode`)は無い**: iPadはWindowGroupが常にフルスクリーンで
///   開くため、Mac版の`applyWindowModeIfNeeded()`/`restoreWindowModeIfNeeded()`
///   (NSWindowを直接操作してウィンドウ内/全画面/PIPを出し分ける処理)は丸ごと不要になった。
/// - **操作はタップ+外部キーボード**: マウスの`onContinuousHover`はiPad単体では発火しない
///   (トラックパッド/Apple Pencilのポインタ接続時のみ)ため、`onTapGesture`でも
///   コントロールオーバーレイを表示できるようにした。キーボード操作はNSEventの代わりに
///   SwiftUIネイティブの`.onKeyPress`(iOS 17+)を使う ― Magic Keyboard等の外部キーボードを
///   接続したiPadでも、スペース/矢印/escでMac版と同じ操作ができる。
struct SlideshowView: View {
    let items: [MediaItem]
    /// スライドショー全体の time limit(分)。`nil`なら無制限。
    let timeLimitMinutes: Int?
    let onExit: () -> Void

    @State private var currentIndex = 0
    @State private var isPaused = false
    @State private var currentImage: UIImage?
    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var photoAdvanceTask: Task<Void, Never>?
    @State private var timeLimitTask: Task<Void, Never>?
    @State private var loadToken = UUID()
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
                        Image(uiImage: currentImage)
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
                        .ignoresSafeArea()
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
        .onTapGesture { revealControls() }
        .onKeyPress(.space) { togglePause(); return .handled }
        .onKeyPress(.leftArrow) { goPrevious(); return .handled }
        .onKeyPress(.rightArrow) { goNext(); return .handled }
        .onKeyPress(.escape) { exit(); return .handled }
        .onAppear {
            setupEngineCallbacks()
            revealControls()
            loadCurrent()
            scheduleTimeLimitIfNeeded()
        }
        .onChange(of: currentIndex) { _, _ in loadCurrent() }
        .onDisappear {
            engine.stop()
            photoAdvanceTask?.cancel()
            hideControlsTask?.cancel()
            timeLimitTask?.cancel()
        }
    }

    private var controlsOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 28) {
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
            .font(.title)
            .foregroundStyle(.white)
            .padding(20)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            .padding(28)
        }
    }

    /// 右下に常時(タップしなくても)表示する撮影日ラベル。
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
}
