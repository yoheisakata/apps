import AppKit
import AVFoundation

// 自動連続再生スライドショー(MySlideshowから移植した機能)。写真は`photoDuration`秒
// 経過で、動画は最後まで再生してから自動的に次へ進む。全画面のみ対応(MySlideshowの
// ウィンドウ内固定サイズ/PIPモードは、MyGalleryの単一ウィンドウ+オーバーレイビューア
// という構造とは相性が悪いため移植していない)。ハイライト再生(動画の一部だけ再生)も
// 移植していない ― MySlideshowで一度実装されたが2026-08-29に完全に撤去された機能で、
// 現在のMySlideshowには存在しない。

/// ファイル名から撮影日らしき`YYYYMMDD`パターンを拾う。MySlideshowの
/// `Core/FilenameDateParser.swift`をそのまま移植したもの ― OneDriveの更新日時は
/// アップロード/同期日時であって撮影日ではないことが多いため、ファイル名だけから
/// 日付を推測する(`modifiedDate`へはフォールバックしない)。
enum FilenameDateParser {
    private static let regex = try! NSRegularExpression(
        pattern: #"(?<![0-9])(19[0-9]{2}|20[0-9]{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12][0-9]|3[01])(?![0-9])"#
    )

    static func date(from fileName: String) -> Date? {
        let range = NSRange(fileName.startIndex..., in: fileName)
        guard let match = regex.firstMatch(in: fileName, range: range),
            let yearRange = Range(match.range(at: 1), in: fileName),
            let monthRange = Range(match.range(at: 2), in: fileName),
            let dayRange = Range(match.range(at: 3), in: fileName),
            let year = Int(fileName[yearRange]),
            let month = Int(fileName[monthRange]),
            let day = Int(fileName[dayRange])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)
    }
}

/// スライドショーの状態機械。`ViewerOverlay`を流用・拡張して使う(新しい別ビューは作らない)
/// ― `overlay.slideshowMode = true`にした上で`onVideoFinished`/`onTogglePause`を設定し、
/// 見た目の追加チロム(コントロールバー・日付ラベル)は`SlideshowControlsView`を
/// 別レイヤーとして上に重ねる。
final class SlideshowController: NSObject {
    private weak var overlay: ViewerOverlay?
    private weak var window: NSWindow?
    private var controlsView: SlideshowControlsView?

    private var order: [PhotoItem] = []
    private var currentIndex = 0
    private(set) var isPaused = false
    private var photoDuration: Double = 6
    private var photoTimer: Timer?
    private var timeLimitTimer: Timer?
    private var autoFullscreenApplied = false

    /// スライドショーが終了した(✕・esc・時間制限)ときに呼ばれる。
    var onExit: (() -> Void)?
    /// 表示中のインデックスが変わるたびに呼ばれる(呼び出し元がグリッドの選択と
    /// 同期させるため)。
    var onIndexChanged: ((Int) -> Void)?

    var isRunning: Bool { overlay != nil }

    func start(overlay: ViewerOverlay, window: NSWindow?, items: [PhotoItem], startIndex: Int,
               shuffle: Bool, photoDuration: Double, timeLimitMinutes: Int?, autoFullscreen: Bool) {
        guard !items.isEmpty else { return }
        self.overlay = overlay
        self.window = window
        self.photoDuration = photoDuration
        isPaused = false

        if shuffle {
            let startItem = items[min(max(startIndex, 0), items.count - 1)]
            var shuffled = items
            shuffled.shuffle()
            order = shuffled
            currentIndex = shuffled.firstIndex(of: startItem) ?? 0
        } else {
            order = items
            currentIndex = startIndex
        }

        overlay.slideshowMode = true
        overlay.onVideoFinished = { [weak self] in self?.advance(by: 1) }
        overlay.onTogglePause = { [weak self] in self?.togglePause() }

        setupControlsView()

        if autoFullscreen, let window, !window.styleMask.contains(.fullScreen) {
            autoFullscreenApplied = true
            window.toggleFullScreen(nil)
        } else {
            autoFullscreenApplied = false
        }

        if let minutes = timeLimitMinutes {
            timeLimitTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in
                self?.stop()
            }
        }

        showCurrent()
    }

    private func showCurrent() {
        guard let overlay, currentIndex >= 0, currentIndex < order.count else { return }
        let item = order[currentIndex]
        overlay.show(photo: item, index: currentIndex, total: order.count)
        controlsView?.setDate(FilenameDateParser.date(from: item.url.lastPathComponent))
        controlsView?.updatePauseIcon(isPaused: isPaused)
        onIndexChanged?(currentIndex)
        scheduleAdvanceIfNeeded(for: item)
    }

    private func scheduleAdvanceIfNeeded(for item: PhotoItem) {
        photoTimer?.invalidate()
        photoTimer = nil
        // 動画は`onVideoFinished`が最後まで再生し終わったら呼ぶので、ここではタイマーを
        // 仕掛けない。写真だけ`photoDuration`秒後に自動的に次へ進める。
        guard !item.isVideo, !isPaused else { return }
        photoTimer = Timer.scheduledTimer(withTimeInterval: photoDuration, repeats: false) { [weak self] _ in
            self?.advance(by: 1)
        }
    }

    func advance(by delta: Int) {
        let next = currentIndex + delta
        guard next >= 0, next < order.count else {
            if delta > 0 { stop() }   // 最後まで行ったら終了(MySlideshowと同じ、ループしない)
            return
        }
        currentIndex = next
        showCurrent()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            photoTimer?.invalidate()
            photoTimer = nil
            overlay?.pauseVideo()
        } else {
            overlay?.resumeVideo()
            if currentIndex < order.count { scheduleAdvanceIfNeeded(for: order[currentIndex]) }
        }
        controlsView?.updatePauseIcon(isPaused: isPaused)
    }

    func stop() {
        guard overlay != nil else { return }
        photoTimer?.invalidate(); photoTimer = nil
        timeLimitTimer?.invalidate(); timeLimitTimer = nil
        controlsView?.removeFromSuperview()
        controlsView = nil
        if autoFullscreenApplied, let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        overlay?.slideshowMode = false
        overlay?.onVideoFinished = nil
        overlay?.onTogglePause = nil
        overlay = nil
        onExit?()
    }

    private func setupControlsView() {
        guard let overlay, let window else { return }
        window.acceptsMouseMovedEvents = true   // マウス移動によるコントロール表示に必要
        let controls = SlideshowControlsView(frame: overlay.bounds)
        controls.autoresizingMask = [.width, .height]
        controls.onPrev = { [weak self] in self?.advance(by: -1) }
        controls.onNext = { [weak self] in self?.advance(by: 1) }
        controls.onTogglePauseTapped = { [weak self] in self?.togglePause() }
        controls.onExit = { [weak self] in self?.stop() }
        overlay.addSubview(controls)
        controlsView = controls
    }
}

/// スライドショーのコントロールバー(前へ/一時停止・再開/次へ/終了)+右下の日付ラベル。
/// マウスを動かすと3秒だけコントロールバーが現れ、動かさないと自動的に隠れる
/// (MySlideshowの`.onContinuousHover`+`Task.sleep`と同じ挙動をAppKitの
/// `NSTrackingArea`+`Timer`で実装したもの)。日付ラベルはコントロールバーと違い
/// 常時表示する(マウスを動かさなくても出続ける)。
final class SlideshowControlsView: NSView {
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onTogglePauseTapped: (() -> Void)?
    var onExit: (() -> Void)?

    private let bar = NSVisualEffectView()
    private let dateLabel = NSTextField(labelWithString: "")
    private let pauseButton = NSButton()
    private var hideTimer: Timer?
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)

        bar.material = .hudWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 12
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        let prevButton = NSButton(image: NSImage(systemSymbolName: "backward.fill", accessibilityDescription: "前へ")!,
                                   target: self, action: #selector(prevTapped))
        pauseButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "一時停止")
        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        let nextButton = NSButton(image: NSImage(systemSymbolName: "forward.fill", accessibilityDescription: "次へ")!,
                                   target: self, action: #selector(nextTapped))
        let exitButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "終了")!,
                                   target: self, action: #selector(exitTapped))
        for b in [prevButton, pauseButton, nextButton, exitButton] {
            b.bezelStyle = .circular
            b.isBordered = false
            b.contentTintColor = .white
        }

        let stack = NSStackView(views: [prevButton, pauseButton, nextButton, exitButton])
        stack.orientation = .horizontal
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        dateLabel.textColor = .white
        dateLabel.font = .systemFont(ofSize: 36, weight: .bold)
        dateLabel.wantsLayer = true
        dateLabel.layer?.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
        dateLabel.layer?.cornerRadius = 8
        dateLabel.isHidden = true
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dateLabel)

        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -14),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            dateLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])

        bar.alphaValue = 0
        bar.isHidden = true
        resetHideTimer()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setDate(_ date: Date?) {
        guard let date else { dateLabel.isHidden = true; return }
        dateLabel.isHidden = false
        dateLabel.stringValue = "  \(Self.dateFormatter.string(from: date))  "
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    func updatePauseIcon(isPaused: Bool) {
        pauseButton.image = NSImage(systemSymbolName: isPaused ? "play.fill" : "pause.fill",
                                     accessibilityDescription: isPaused ? "再開" : "一時停止")
    }

    // MARK: mouse-move reveal / auto-hide

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                   owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        showBar()
    }

    private func showBar() {
        bar.isHidden = false
        bar.animator().alphaValue = 1
        resetHideTimer()
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.hideBar()
        }
    }

    private func hideBar() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            bar.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.bar.isHidden = true })
    }

    /// コントロールバー・日付ラベル以外への クリック・ダブルクリックは、下にある
    /// `ViewerOverlay`(ダブルクリックで閉じる等)へそのまま通す。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        if bar.frame.contains(local) || (!dateLabel.isHidden && dateLabel.frame.contains(local)) {
            return super.hitTest(point)
        }
        return nil
    }

    @objc private func prevTapped() { onPrev?(); showBar() }
    @objc private func nextTapped() { onNext?(); showBar() }
    @objc private func pauseTapped() { onTogglePauseTapped?(); showBar() }
    @objc private func exitTapped() { onExit?() }
}
