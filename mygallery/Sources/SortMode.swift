import AppKit

// 手動の璃央仕分け(2026-11-09)。Tinder風に写真を1枚ずつ表示し、
// → (右) = 璃央が写っている / ← (左) = 璃央以外(削除候補)として仕分ける。
// 結果は`ManualLabelStore`に永続化され、フィルターの「仕分け」で絞り込める。
// 左に仕分けても**その場では削除しない**(削除は表示メニューの「璃央以外をゴミ箱へ」で
// 確認の上まとめて行う)。自動判定(`RioMatcher.swift`)とは独立した仕組み。

enum ManualLabel: String, Codable {
    case rio, other
}

enum ManualFilter: Int {
    case all = 0, rio, other, unlabeled
}

/// 写真パス → 仕分け結果。`~/Library/Application Support/MyGallery/rio-labels.json`。
final class ManualLabelStore {
    static let shared = ManualLabelStore()
    private var labels: [String: ManualLabel] = [:]
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "mygallery.manual-labels")
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyGallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rio-labels.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: ManualLabel].self, from: data) {
            labels = dict
        }
    }

    func label(for item: PhotoItem) -> ManualLabel? {
        lock.lock(); defer { lock.unlock() }
        return labels[item.cacheKey]
    }

    func set(_ label: ManualLabel?, for item: PhotoItem) {
        lock.lock()
        if let label { labels[item.cacheKey] = label } else { labels.removeValue(forKey: item.cacheKey) }
        let snapshot = labels
        lock.unlock()
        save(snapshot)
    }

    func remove(paths: [String]) {
        lock.lock()
        for p in paths { labels.removeValue(forKey: p) }
        let snapshot = labels
        lock.unlock()
        save(snapshot)
    }

    func clear() {
        lock.lock(); labels = [:]; lock.unlock()
        save([:])
    }

    var counts: (rio: Int, other: Int) {
        lock.lock(); defer { lock.unlock() }
        return (labels.values.filter { $0 == .rio }.count, labels.values.filter { $0 == .other }.count)
    }

    private func save(_ snapshot: [String: ManualLabel]) {
        let url = fileURL
        writeQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
}

/// 全画面の仕分けビュー。キー: → 璃央 / ← 璃央以外 / ↓・Space スキップ / ↑・⌫・⌘Z 元に戻す / Esc 終了。
/// マウスでは下のボタン、または画像を左右へ一定以上ドラッグ(スワイプ)でも仕分けられる。
final class SortOverlay: NSView {
    var onExit: (() -> Void)?

    private let items: [PhotoItem]
    private var index = 0
    private var history: [(index: Int, labeled: Bool)] = []
    private var sessionRio = 0
    private var sessionOther = 0
    private var images: [Int: NSImage] = [:]
    private var loading: Set<Int> = []

    private let imageView = FillImageView(gravity: .resizeAspect)
    private let infoLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let doneLabel = NSTextField(labelWithString: "")
    private let flashView = NSView()
    private let otherButton = NSButton(title: "← 璃央以外", target: nil, action: nil)
    private let rioButton = NSButton(title: "璃央 →", target: nil, action: nil)
    private let skipButton = NSButton(title: "スキップ ↓", target: nil, action: nil)
    private let undoButton = NSButton(title: "元に戻す ↑", target: nil, action: nil)
    private let exitButton = NSButton(title: "終了 Esc", target: nil, action: nil)
    private var dragStartX: CGFloat?

    init(frame: NSRect, items: [PhotoItem]) {
        self.items = items
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(imageView)

        flashView.wantsLayer = true
        flashView.alphaValue = 0
        flashView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(flashView)

        for l in [infoLabel, hintLabel] {
            l.textColor = .white
            l.alignment = .center
            l.wantsLayer = true
            l.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
            l.layer?.cornerRadius = 9
            l.translatesAutoresizingMaskIntoConstraints = false
            addSubview(l)
        }
        infoLabel.font = .systemFont(ofSize: 12)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.stringValue = "  → 璃央  /  ← 璃央以外(削除候補・まだ削除はされません)  /  ↓ スキップ  /  ↑ 元に戻す  "

        doneLabel.textColor = .white
        doneLabel.font = .boldSystemFont(ofSize: 22)
        doneLabel.alignment = .center
        doneLabel.isHidden = true
        doneLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doneLabel)

        let buttons: [(NSButton, Selector, NSColor?)] = [
            (otherButton, #selector(tapOther), NSColor.systemRed),
            (skipButton, #selector(tapSkip), nil),
            (undoButton, #selector(tapUndo), nil),
            (rioButton, #selector(tapRio), NSColor.systemGreen),
            (exitButton, #selector(tapExit), nil),
        ]
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 14
        bar.translatesAutoresizingMaskIntoConstraints = false
        for (b, sel, color) in buttons {
            b.target = self
            b.action = sel
            b.bezelStyle = .rounded
            b.controlSize = .large
            b.focusRingType = .none
            if let color { b.bezelColor = color }
            bar.addArrangedSubview(b)
        }
        addSubview(bar)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -90),
            flashView.leadingAnchor.constraint(equalTo: leadingAnchor),
            flashView.trailingAnchor.constraint(equalTo: trailingAnchor),
            flashView.topAnchor.constraint(equalTo: topAnchor),
            flashView.bottomAnchor.constraint(equalTo: bottomAnchor),
            infoLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            infoLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),
            bar.centerXAnchor.constraint(equalTo: centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            doneLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            doneLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        show()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: 表示

    private func show() {
        if index >= items.count {
            imageView.image = nil
            doneLabel.stringValue = "仕分け完了(璃央 \(sessionRio) / 璃央以外 \(sessionOther))\nEsc で終了"
            doneLabel.isHidden = false
            [otherButton, rioButton, skipButton].forEach { $0.isEnabled = false }
            infoLabel.stringValue = "  \(items.count) / \(items.count)  "
            return
        }
        doneLabel.isHidden = true
        [otherButton, rioButton, skipButton].forEach { $0.isEnabled = true }
        undoButton.isEnabled = !history.isEmpty
        let item = items[index]
        infoLabel.stringValue = "  \(item.name) — \(index + 1) / \(items.count)    璃央 \(sessionRio) / 璃央以外 \(sessionOther)  "
        imageView.image = images[index]
        load(index)
        for k in 1...2 { load(index + k) }
        for k in images.keys where k < index - 2 || k > index + 3 { images.removeValue(forKey: k) }
    }

    private func load(_ i: Int) {
        guard i >= 0, i < items.count, images[i] == nil, !loading.contains(i) else { return }
        loading.insert(i)
        let url = items[i].url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let img = ThumbnailLoader.generate(url: url, isVideo: false, maxPixel: 2048)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading.remove(i)
                guard let img else { return }
                self.images[i] = img
                if i == self.index { self.imageView.image = img }
            }
        }
    }

    private func flash(_ color: NSColor) {
        flashView.layer?.backgroundColor = color.withAlphaComponent(0.35).cgColor
        flashView.alphaValue = 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            flashView.animator().alphaValue = 0
        }
    }

    // MARK: 操作

    private func decide(_ label: ManualLabel) {
        guard index < items.count else { return }
        ManualLabelStore.shared.set(label, for: items[index])
        history.append((index, true))
        if label == .rio { sessionRio += 1; flash(.systemGreen) } else { sessionOther += 1; flash(.systemRed) }
        index += 1
        show()
    }

    private func skip() {
        guard index < items.count else { return }
        history.append((index, false))
        index += 1
        show()
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        if last.labeled {
            if ManualLabelStore.shared.label(for: items[last.index]) == .rio { sessionRio -= 1 } else { sessionOther -= 1 }
            ManualLabelStore.shared.set(nil, for: items[last.index])
        }
        index = last.index
        show()
    }

    @objc private func tapRio() { decide(.rio); window?.makeFirstResponder(self) }
    @objc private func tapOther() { decide(.other); window?.makeFirstResponder(self) }
    @objc private func tapSkip() { skip(); window?.makeFirstResponder(self) }
    @objc private func tapUndo() { undo(); window?.makeFirstResponder(self) }
    @objc private func tapExit() { onExit?() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 124: decide(.rio)             // →
        case 123: decide(.other)           // ←
        case 125, 49: skip()               // ↓ / Space
        case 126, 51: undo()               // ↑ / Delete
        case 6 where event.modifierFlags.contains(.command): undo()   // ⌘Z
        case 53: onExit?()                 // Esc
        default: super.keyDown(with: event)
        }
    }

    // スワイプ(画像を左右へドラッグ)
    override func mouseDown(with event: NSEvent) {
        dragStartX = convert(event.locationInWindow, from: nil).x
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStartX = nil }
        guard let x0 = dragStartX else { return }
        let dx = convert(event.locationInWindow, from: nil).x - x0
        if dx > 120 { decide(.rio) } else if dx < -120 { decide(.other) }
    }
}
