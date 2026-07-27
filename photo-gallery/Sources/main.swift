// Photo Gallery — Photos.app 風のローカルフォルダ・ギャラリー(取り込みなし)。
//
// ルートフォルダ配下の画像を再帰スキャンし、
//   サイドバー(フォルダツリー) + サムネイルグリッド + フルサイズビューア
// で閲覧・整理する。ファイルはコピーもインポートもしない — 見るのは常に実ファイル。
//
// 単一ファイルの AppKit アプリ(WKWebView なし、依存なし、実行時ネットワークなし)。

import AppKit
import ImageIO
import CryptoKit

// MARK: - Configuration

/// ImageIO でデコードできる代表的な画像拡張子(RAW 含む)。
private let imageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "heic", "heif", "webp",
    "tif", "tiff", "bmp", "jp2", "avif",
    "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf",
]

private let defaultsRootKey = "rootPath"
private let defaultsSortKey = "sortOrder"
private let defaultsCellKey = "cellSize"

private let minCellSize: CGFloat = 96
private let maxCellSize: CGFloat = 320
private let defaultCellSize: CGFloat = 160

enum SortOrder: Int {
    case dateDesc = 0   // 新しい順(既定)
    case dateAsc = 1    // 古い順
    case name = 2       // 名前順
}

// MARK: - Model

struct PhotoItem: Equatable {
    let url: URL
    let mtime: Date
    static func == (a: PhotoItem, b: PhotoItem) -> Bool { a.url == b.url }
}

/// サイドバーのフォルダツリー。NSOutlineView の item として使うので NSObject。
final class FolderNode: NSObject {
    let url: URL
    let name: String
    weak var parent: FolderNode?
    var children: [FolderNode] = []
    var totalCount = 0   // このサブツリー配下の画像枚数

    init(url: URL, parent: FolderNode?) {
        self.url = url
        self.name = url.lastPathComponent
        self.parent = parent
    }
}

// MARK: - Photo store (scan + tree)

final class PhotoStore {
    private(set) var rootURL: URL?
    private(set) var photos: [PhotoItem] = []
    private(set) var rootNode: FolderNode?
    private(set) var isScanning = false
    private var scanGeneration = 0

    var onScanFinished: (() -> Void)?

    func setRoot(_ url: URL) {
        rootURL = url.standardizedFileURL
        UserDefaults.standard.set(rootURL!.path, forKey: defaultsRootKey)
        rescan()
    }

    /// バックグラウンドで再帰スキャン。隠しファイルと .app/.photoslibrary 等のパッケージ内は除外。
    func rescan() {
        guard let root = rootURL else { return }
        scanGeneration += 1
        let gen = scanGeneration
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var items: [PhotoItem] = []
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
            if let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let u as URL in e {
                    guard imageExtensions.contains(u.pathExtension.lowercased()) else { continue }
                    guard let rv = try? u.resourceValues(forKeys: keys), rv.isRegularFile == true
                    else { continue }
                    items.append(PhotoItem(url: u.standardizedFileURL,
                                           mtime: rv.contentModificationDate ?? .distantPast))
                }
            }
            DispatchQueue.main.async {
                guard let self = self, self.scanGeneration == gen else { return }
                self.photos = items
                self.rebuildTree()
                self.isScanning = false
                self.onScanFinished?()
            }
        }
    }

    /// ゴミ箱移動などでファイルが消えた後、メモリ上のモデルだけ更新(再スキャン不要)。
    func removePhotos(withPaths paths: Set<String>) {
        photos.removeAll { paths.contains($0.url.path) }
        rebuildTree()
    }

    func photos(under node: FolderNode?, order: SortOrder) -> [PhotoItem] {
        var list: [PhotoItem]
        if let node = node, let root = rootNode, node !== root {
            let prefix = node.url.path + "/"
            list = photos.filter { $0.url.path.hasPrefix(prefix) }
        } else {
            list = photos
        }
        switch order {
        case .name:
            list.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        case .dateDesc:
            list.sort { $0.mtime > $1.mtime }
        case .dateAsc:
            list.sort { $0.mtime < $1.mtime }
        }
        return list
    }

    func findNode(path: String) -> FolderNode? {
        guard let root = rootNode else { return nil }
        var stack = [root]
        while let n = stack.popLast() {
            if n.url.path == path { return n }
            stack.append(contentsOf: n.children)
        }
        return nil
    }

    /// photos の親ディレクトリ群からフォルダツリーを組み立てる(画像を含むフォルダのみ)。
    private func rebuildTree() {
        guard let root = rootURL else { rootNode = nil; return }
        let newRoot = FolderNode(url: root, parent: nil)
        var nodes: [String: FolderNode] = [root.path: newRoot]

        for p in photos {
            // 画像の親ディレクトリから root までのチェーンを収集(root 直下 → 親の順に積む)
            var chain: [URL] = []
            var dir = p.url.deletingLastPathComponent()
            while dir.path.count > root.path.count {
                chain.append(dir)
                let up = dir.deletingLastPathComponent()
                if up.path == dir.path { break }   // "/" で停止(保険)
                dir = up
            }
            guard dir.path == root.path else { continue }   // root 外(通常あり得ない)

            var parent = newRoot
            for u in chain.reversed() {
                if let n = nodes[u.path] {
                    parent = n
                } else {
                    let n = FolderNode(url: u, parent: parent)
                    nodes[u.path] = n
                    parent.children.append(n)
                    parent = n
                }
            }
            newRoot.totalCount += 1
            for u in chain { nodes[u.path]?.totalCount += 1 }
        }

        func sortRec(_ n: FolderNode) {
            n.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            n.children.forEach(sortRec)
        }
        sortRec(newRoot)
        rootNode = newRoot
    }
}

// MARK: - Thumbnail loader

/// CGImageSource のサムネイル生成(EXIF 回転込み・ダウンサンプル)を並列 4 本で回し、
/// NSCache に載せる。リクエストは main スレッドから呼ぶ前提(waiters を main で管理)。
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    static let gridMaxPixel: CGFloat = 512    // Retina で cell 256pt まで十分な解像度

    /// グリッドサムネイルのディスクキャッシュ。再起動後も同じフォルダなら再生成不要にする。
    private static let diskCacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.yosakata.photo-gallery/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let maxDiskCacheBytes: Int64 = 1_500_000_000   // 上限 1.5GB(超えたら古い順に削除)
    private static let jpegQuality: CGFloat = 0.6

    private let cache = NSCache<NSString, NSImage>()
    private var waiters: [String: [(NSImage?) -> Void]] = [:]
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .userInitiated
        return q
    }()

    private init() { cache.countLimit = 1500 }

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    /// mtime も鍵に含めるので、ファイルが更新されればディスクキャッシュは自動的に無効化される。
    func request(_ url: URL, mtime: Date, completion: @escaping (URL, NSImage?) -> Void) {
        let key = url.path
        if let img = cache.object(forKey: key as NSString) { completion(url, img); return }
        if waiters[key] != nil {
            waiters[key]!.append { completion(url, $0) }
            return
        }
        waiters[key] = [{ completion(url, $0) }]
        queue.addOperation { [weak self] in
            guard let self = self else { return }
            let diskURL = ThumbnailLoader.diskCacheURL(for: url, mtime: mtime)
            var img: NSImage?
            if let cg = ThumbnailLoader.loadDiskCG(diskURL) {
                img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                ThumbnailLoader.touch(diskURL)
            } else if let cg = ThumbnailLoader.generateCG(url: url, maxPixel: ThumbnailLoader.gridMaxPixel) {
                img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                ThumbnailLoader.writeDiskCG(cg, to: diskURL)
            }
            DispatchQueue.main.async {
                if let img = img { self.cache.setObject(img, forKey: key as NSString) }
                for cb in self.waiters.removeValue(forKey: key) ?? [] { cb(img) }
            }
        }
    }

    static func generate(url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let cg = generateCG(url: url, maxPixel: maxPixel) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func generateCG(url: URL, maxPixel: CGFloat) -> CGImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,     // EXIF の回転を反映
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as [CFString: Any] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts)
    }

    // MARK: disk cache

    private static func diskCacheURL(for url: URL, mtime: Date) -> URL {
        let raw = "\(url.path)|\(mtime.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(hex).appendingPathExtension("jpg")
    }

    private static func loadDiskCG(_ diskURL: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(diskURL as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func writeDiskCG(_ cg: CGImage, to diskURL: URL) {
        guard let dest = CGImageDestinationCreateWithURL(diskURL as CFURL, "public.jpeg" as CFString, 1, nil)
        else { return }
        let opts = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(dest, cg, opts)
        CGImageDestinationFinalize(dest)
        // 書き込みのたびに走査するのは無駄なので、確率的に間引いて上限チェックする。
        if Int.random(in: 0..<300) == 0 { pruneDiskCacheIfNeeded() }
    }

    /// キャッシュファイルの更新日時を touch して LRU の「最近使った」扱いにする。
    private static func touch(_ diskURL: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: diskURL.path)
    }

    private static func pruneDiskCacheIfNeeded() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: diskCacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return }
        var entries: [(url: URL, size: Int64, mtime: Date)] = urls.compactMap { u in
            guard let rv = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = rv.fileSize else { return nil }
            return (u, Int64(size), rv.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxDiskCacheBytes else { return }
        entries.sort { $0.mtime < $1.mtime }   // 古い(=最近アクセスしていない)順
        let target = Int64(Double(maxDiskCacheBytes) * 0.8)   // 削りすぎないよう 80% まで戻す
        for e in entries {
            if total <= target { break }
            try? fm.removeItem(at: e.url)
            total -= e.size
        }
    }
}

// MARK: - FillImageView

/// CALayer の contentsGravity で aspect-fill(グリッド)/ aspect-fit(ビューア)描画する軽量ビュー。
final class FillImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    init(gravity: CALayerContentsGravity) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = gravity
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.12).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let scale = window?.backingScaleFactor ?? 2
        layer?.contents = image?.layerContents(forContentsScale: scale)
        layer?.contentsScale = scale
    }
}

// MARK: - Grid cell

final class PhotoCell: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("PhotoCell")

    private let fill = FillImageView(gravity: .resizeAspectFill)
    private var currentPath: String?

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 5
        v.layer?.masksToBounds = true
        fill.frame = v.bounds
        fill.autoresizingMask = [.width, .height]
        v.addSubview(fill)
        view = v
    }

    func configure(with photo: PhotoItem) {
        currentPath = photo.url.path
        view.toolTip = photo.url.lastPathComponent
        if let img = ThumbnailLoader.shared.cached(photo.url) {
            fill.image = img
            return
        }
        fill.image = nil
        ThumbnailLoader.shared.request(photo.url, mtime: photo.mtime) { [weak self] url, img in
            guard let self = self, self.currentPath == url.path else { return }
            self.fill.image = img
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentPath = nil
        fill.image = nil
        view.toolTip = nil
    }

    override var isSelected: Bool { didSet { updateBorder() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateBorder() } }

    private func updateBorder() {
        let on = isSelected || highlightState == .forSelection
        view.layer?.borderWidth = on ? 3 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }
}

// MARK: - Grid collection view (double-click / keys / folder drop)

final class GridCollectionView: NSCollectionView {
    var onOpen: ((Int) -> Void)?
    var onDropFolder: ((URL) -> Void)?
    var onSelectionChanged: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            let pt = convert(event.locationInWindow, from: nil)
            if let ip = indexPathForItem(at: pt) { onOpen?(ip.item) }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76:   // Return / Space / Enter → ビューアを開く
            if let ip = selectionIndexPaths.sorted().first {
                onOpen?(ip.item)
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    // 右クリック: カーソル下のアイテムが未選択なら選択してからメニューを出す(Finder 流)
    override func menu(for event: NSEvent) -> NSMenu? {
        let pt = convert(event.locationInWindow, from: nil)
        if let ip = indexPathForItem(at: pt), !selectionIndexPaths.contains(ip) {
            deselectAll(nil)
            selectItems(at: [ip], scrollPosition: [])
            onSelectionChanged?()
        }
        return super.menu(for: event)
    }

    // フォルダのドロップでルートを切り替え
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFolderURL(sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedFolderURL(sender) else { return false }
        onDropFolder?(url)
        return true
    }

    private func droppedFolderURL(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let u = urls?.first else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return u
    }
}

// MARK: - Grid view controller

final class GridViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let collectionView = GridCollectionView(frame: .zero)
    let layout = NSCollectionViewFlowLayout()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "フォルダを開く…", target: nil,
                                      action: #selector(MainWindowController.openFolder(_:)))

    var items: [PhotoItem] = [] {
        didSet {
            collectionView.reloadData()
            collectionView.onSelectionChanged?()
        }
    }

    var cellSize: CGFloat = defaultCellSize {
        didSet {
            layout.itemSize = NSSize(width: cellSize, height: cellSize)
            layout.invalidateLayout()
        }
    }

    override func loadView() {
        let root = NSView()
        root.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        layout.itemSize = NSSize(width: cellSize, height: cellSize)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(PhotoCell.self, forItemWithIdentifier: PhotoCell.reuseID)

        scroll.documentView = collectionView
        scroll.hasVerticalScroller = true
        scroll.frame = root.bounds
        scroll.autoresizingMask = [.width, .height]
        root.addSubview(scroll)

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(openButton)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -20),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -60),
            openButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            openButton.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 14),
        ])

        view = root
        setEmptyState("フォルダを開いてください(⌘O)\nウインドウへのフォルダのドロップでも開けます", showButton: true)
    }

    func setEmptyState(_ message: String?, showButton: Bool = false) {
        emptyLabel.stringValue = message ?? ""
        emptyLabel.isHidden = (message == nil)
        openButton.isHidden = !(showButton && message != nil)
    }

    var selectedItems: [PhotoItem] {
        collectionView.selectionIndexPaths.sorted().compactMap {
            $0.item < items.count ? items[$0.item] : nil
        }
    }

    func select(index: Int) {
        guard index >= 0, index < items.count else { return }
        let ip = IndexPath(item: index, section: 0)
        collectionView.deselectAll(nil)
        collectionView.selectItems(at: [ip], scrollPosition: .nearestHorizontalEdge)
        collectionView.onSelectionChanged?()
    }

    // MARK: data source

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ cv: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = cv.makeItem(withIdentifier: PhotoCell.reuseID, for: indexPath) as! PhotoCell
        cell.configure(with: items[indexPath.item])
        return cell
    }

    // MARK: delegate

    func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.onSelectionChanged?()
    }

    func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.onSelectionChanged?()
    }

    // 他アプリ(Finder / メール等)へのドラッグ
    func collectionView(_ cv: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        items[indexPath.item].url as NSURL
    }
}

// MARK: - Sidebar

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let outline = NSOutlineView()
    var onSelect: ((FolderNode?) -> Void)?

    private(set) var rootNode: FolderNode?
    private var suppressSelectionCallback = false
    private let cellID = NSUserInterfaceItemIdentifier("SidebarCell")

    override func loadView() {
        let scroll = NSScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 220, height: 600)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folders"))
        col.isEditable = false
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.allowsEmptySelection = true
        outline.dataSource = self
        outline.delegate = self
        outline.autoresizesOutlineColumn = true

        scroll.documentView = outline
        view = scroll
    }

    /// ツリーを差し替え、可能なら以前と同じフォルダを選択し直す。
    func setRoot(_ node: FolderNode?, selectPath: String?) {
        rootNode = node
        suppressSelectionCallback = true
        outline.reloadData()
        if let root = node {
            outline.expandItem(root)
            var target = root
            if let path = selectPath, let found = find(path: path, in: root) {
                target = found
                var chain: [FolderNode] = []
                var p = found.parent
                while let n = p { chain.append(n); p = n.parent }
                for n in chain.reversed() { outline.expandItem(n) }
            }
            let row = outline.row(forItem: target)
            if row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        suppressSelectionCallback = false
    }

    var selectedNode: FolderNode? {
        outline.item(atRow: outline.selectedRow) as? FolderNode
    }

    private func find(path: String, in node: FolderNode) -> FolderNode? {
        if node.url.path == path { return node }
        for c in node.children {
            if let f = find(path: path, in: c) { return f }
        }
        return nil
    }

    // MARK: data source

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNode == nil ? 0 : 1 }
        return (item as! FolderNode).children.count
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNode! }
        return (item as! FolderNode).children[index]
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !(item as! FolderNode).children.isEmpty
    }

    // MARK: delegate

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! FolderNode
        let cell = ov.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView ?? makeCell()
        let isRoot = node === rootNode
        cell.textField?.stringValue =
            (isRoot ? "すべての写真" : node.name) + " (\(node.totalCount))"
        cell.imageView?.image = NSImage(
            systemSymbolName: isRoot ? "photo.on.rectangle" : "folder",
            accessibilityDescription: nil)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback else { return }
        onSelect?(selectedNode)
    }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = cellID
        let iv = NSImageView()
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        iv.translatesAutoresizingMaskIntoConstraints = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(iv)
        cell.addSubview(tf)
        cell.imageView = iv
        cell.textField = tf
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - Viewer overlay

/// グリッドの上に被せるフルサイズビューア。Esc / Space で閉じる、← → で移動、⌫ でゴミ箱。
final class ViewerOverlay: NSView {
    var onClose: (() -> Void)?
    var onStep: ((Int) -> Void)?

    private let imageView = FillImageView(gravity: .resizeAspect)
    private let infoLabel = NSTextField(labelWithString: "")
    private var currentPath: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        infoLabel.textColor = .white
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.alignment = .center
        infoLabel.wantsLayer = true
        infoLabel.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        infoLabel.layer?.cornerRadius = 9
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            infoLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            infoLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(photo: PhotoItem, index: Int, total: Int) {
        currentPath = photo.url.path
        infoLabel.stringValue = "  \(photo.url.lastPathComponent) — \(index + 1) / \(total)  "
        // まずグリッドのサムネイルを即表示し、裏で高解像度(最大 4096px)を読む
        imageView.image = ThumbnailLoader.shared.cached(photo.url)
        let url = photo.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let img = ThumbnailLoader.generate(url: url, maxPixel: 4096)
            DispatchQueue.main.async {
                guard let self = self, self.currentPath == url.path else { return }
                if let img = img { self.imageView.image = img }
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53, 49:   // Esc / Space
            onClose?()
        case 123, 126: // ← / ↑
            onStep?(-1)
        case 124, 125: // → / ↓
            onStep?(1)
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onClose?() }
    }
}

// MARK: - Main window controller

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSMenuItemValidation {
    private let store = PhotoStore()
    private let sidebarVC = SidebarViewController()
    private let gridVC = GridViewController()
    private let splitVC = NSSplitViewController()
    private var viewer: ViewerOverlay?
    private var viewerIndex = 0
    private var slider: NSSlider!

    private var currentFolderPath: String?
    private var sortOrder: SortOrder = .dateDesc {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: defaultsSortKey) }
    }

    private static let thumbSliderItemID = NSToolbarItem.Identifier("thumbSize")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Photo Gallery"
        window.toolbarStyle = .unified
        window.center()
        self.init(window: window)

        if let saved = SortOrder(rawValue: UserDefaults.standard.integer(forKey: defaultsSortKey)) {
            sortOrder = saved
        }
        let savedCell = UserDefaults.standard.double(forKey: defaultsCellKey)
        if savedCell >= Double(minCellSize), savedCell <= Double(maxCellSize) {
            gridVC.cellSize = CGFloat(savedCell)
        }

        setupSplitView()
        setupToolbar()
        setupCallbacks()
        window.setFrameAutosaveName("PhotoGalleryMain")

        // 前回のルートを復元(消えていたら空状態のまま)
        if let path = UserDefaults.standard.string(forKey: defaultsRootKey) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                setRoot(URL(fileURLWithPath: path))
            }
        }
    }

    private func setupSplitView() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 340
        splitVC.addSplitViewItem(sidebarItem)

        let contentItem = NSSplitViewItem(viewController: gridVC)
        contentItem.minimumThickness = 400
        splitVC.addSplitViewItem(contentItem)

        window?.contentViewController = splitVC
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    private func setupCallbacks() {
        store.onScanFinished = { [weak self] in self?.scanFinished() }

        sidebarVC.onSelect = { [weak self] node in
            guard let self = self else { return }
            self.currentFolderPath = node?.url.path
            self.reloadGrid()
        }

        gridVC.collectionView.onOpen = { [weak self] index in self?.openViewer(at: index) }
        gridVC.collectionView.onDropFolder = { [weak self] url in self?.setRoot(url) }
        gridVC.collectionView.onSelectionChanged = { [weak self] in self?.updateSubtitle() }

        // グリッドの右クリックメニュー(nil ターゲット → レスポンダチェーン経由で self)
        let menu = NSMenu()
        menu.addItem(withTitle: "Finder で表示",
                     action: #selector(revealInFinder(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "コピー", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "ゴミ箱に入れる",
                     action: #selector(trashSelection(_:)), keyEquivalent: "")
        gridVC.collectionView.menu = menu
    }

    // MARK: root / reload

    func setRoot(_ url: URL) {
        closeViewer()
        currentFolderPath = nil
        window?.title = url.lastPathComponent
        gridVC.items = []
        gridVC.setEmptyState("読み込み中…")
        store.setRoot(url)
    }

    private func scanFinished() {
        sidebarVC.setRoot(store.rootNode, selectPath: currentFolderPath)
        currentFolderPath = sidebarVC.selectedNode?.url.path
        reloadGrid()
    }

    private func reloadGrid() {
        let node = currentFolderPath.flatMap { store.findNode(path: $0) }
        gridVC.items = store.photos(under: node, order: sortOrder)
        if store.rootURL == nil {
            gridVC.setEmptyState(
                "フォルダを開いてください(⌘O)\nウインドウへのフォルダのドロップでも開けます",
                showButton: true)
        } else if gridVC.items.isEmpty {
            gridVC.setEmptyState(store.isScanning ? "読み込み中…" : "写真が見つかりません")
        } else {
            gridVC.setEmptyState(nil)
        }
        updateSubtitle()
    }

    private func updateSubtitle() {
        guard let window = window else { return }
        if store.rootURL == nil {
            window.subtitle = ""
            return
        }
        let n = gridVC.items.count
        let sel = gridVC.collectionView.selectionIndexPaths.count
        window.subtitle = sel > 0 ? "\(n) 枚(\(sel) 枚選択)" : "\(n) 枚"
    }

    // MARK: viewer

    private func openViewer(at index: Int) {
        guard index >= 0, index < gridVC.items.count, let contentView = window?.contentView
        else { return }
        if viewer == nil {
            let v = ViewerOverlay(frame: contentView.bounds)
            v.autoresizingMask = [.width, .height]
            v.onClose = { [weak self] in self?.closeViewer() }
            v.onStep = { [weak self] d in self?.stepViewer(d) }
            viewer = v
        }
        viewerIndex = index
        viewer!.frame = contentView.bounds
        contentView.addSubview(viewer!)
        viewer!.show(photo: gridVC.items[index], index: index, total: gridVC.items.count)
        window?.makeFirstResponder(viewer)
    }

    private func stepViewer(_ delta: Int) {
        let next = viewerIndex + delta
        guard next >= 0, next < gridVC.items.count else { return }
        viewerIndex = next
        viewer?.show(photo: gridVC.items[next], index: next, total: gridVC.items.count)
    }

    private func closeViewer() {
        guard let v = viewer, v.superview != nil else { return }
        v.removeFromSuperview()
        gridVC.select(index: viewerIndex)
        window?.makeFirstResponder(gridVC.collectionView)
    }

    private var viewerVisible: Bool { viewer?.superview != nil }

    // MARK: actions (メニュー / ツールバーから、nil ターゲットのレスポンダチェーン経由)

    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "このフォルダを表示"
        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url)
        }
    }

    @objc func refresh(_ sender: Any?) {
        guard store.rootURL != nil else { return }
        closeViewer()
        store.rescan()
    }

    @objc func revealInFinder(_ sender: Any?) {
        let urls = targetPhotos().map { $0.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func copy(_ sender: Any?) {
        let urls = targetPhotos().map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls)
    }

    @objc func trashSelection(_ sender: Any?) {
        let targets = targetPhotos()
        guard !targets.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = targets.count == 1
            ? "“\(targets[0].url.lastPathComponent)” をゴミ箱に入れますか?"
            : "\(targets.count) 枚の写真をゴミ箱に入れますか?"
        alert.informativeText = "Finder のゴミ箱からいつでも戻せます。"
        alert.addButton(withTitle: "ゴミ箱に入れる")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var removed = Set<String>()
        var failures: [String] = []
        for p in targets {
            do {
                try FileManager.default.trashItem(at: p.url, resultingItemURL: nil)
                removed.insert(p.url.path)
            } catch {
                failures.append(p.url.lastPathComponent)
            }
        }
        store.removePhotos(withPaths: removed)
        sidebarVC.setRoot(store.rootNode, selectPath: currentFolderPath)
        currentFolderPath = sidebarVC.selectedNode?.url.path
        reloadGrid()

        if viewerVisible {
            if gridVC.items.isEmpty {
                closeViewer()
            } else {
                viewerIndex = min(viewerIndex, gridVC.items.count - 1)
                viewer?.show(photo: gridVC.items[viewerIndex],
                             index: viewerIndex, total: gridVC.items.count)
            }
        }

        if !failures.isEmpty {
            let a = NSAlert()
            a.messageText = "ゴミ箱に入れられなかったファイルがあります"
            a.informativeText = failures.joined(separator: "\n")
            a.runModal()
        }
    }

    @objc func changeSort(_ sender: NSMenuItem) {
        guard let order = SortOrder(rawValue: sender.tag) else { return }
        sortOrder = order
        reloadGrid()
    }

    @objc func zoomIn(_ sender: Any?)  { setCellSize(gridVC.cellSize + 32) }
    @objc func zoomOut(_ sender: Any?) { setCellSize(gridVC.cellSize - 32) }

    @objc private func sliderChanged(_ sender: NSSlider) {
        setCellSize(CGFloat(sender.doubleValue))
    }

    private func setCellSize(_ size: CGFloat) {
        let s = min(max(size, minCellSize), maxCellSize)
        gridVC.cellSize = s
        slider?.doubleValue = Double(s)
        UserDefaults.standard.set(Double(s), forKey: defaultsCellKey)
    }

    /// メニュー操作の対象: ビューア表示中は表示中の 1 枚、それ以外はグリッドの選択。
    private func targetPhotos() -> [PhotoItem] {
        if viewerVisible {
            guard viewerIndex < gridVC.items.count else { return [] }
            return [gridVC.items[viewerIndex]]
        }
        return gridVC.selectedItems
    }

    // MARK: menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(revealInFinder(_:)), #selector(copy(_:)), #selector(trashSelection(_:)):
            return !targetPhotos().isEmpty
        case #selector(refresh(_:)):
            return store.rootURL != nil
        case #selector(changeSort(_:)):
            menuItem.state = (menuItem.tag == sortOrder.rawValue) ? .on : .off
            return store.rootURL != nil
        case #selector(zoomIn(_:)):
            return gridVC.cellSize < maxCellSize
        case #selector(zoomOut(_:)):
            return gridVC.cellSize > minCellSize
        default:
            return true
        }
    }

    // MARK: toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, Self.thumbSliderItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.thumbSliderItemID else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "サムネイルサイズ"
        item.paletteLabel = "サムネイルサイズ"
        let s = NSSlider(value: Double(gridVC.cellSize),
                         minValue: Double(minCellSize), maxValue: Double(maxCellSize),
                         target: self, action: #selector(sliderChanged(_:)))
        s.isContinuous = true
        s.widthAnchor.constraint(equalToConstant: 140).isActive = true
        slider = s
        item.view = s
        return item
    }
}

// MARK: - App delegate & menu

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWC: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        mainWC = MainWindowController()
        mainWC.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Finder の「このアプリケーションで開く」やアイコンへのフォルダドロップ
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filename, isDirectory: &isDir),
              isDir.boolValue else { return false }
        mainWC?.setRoot(URL(fileURLWithPath: filename))
        return true
    }

    private func buildMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Photo Gallery について",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Photo Gallery を隠す",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Photo Gallery を終了",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "ファイル")
        fileMenu.addItem(withTitle: "フォルダを開く…",
                         action: #selector(MainWindowController.openFolder(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "再読み込み",
                         action: #selector(MainWindowController.refresh(_:)), keyEquivalent: "r")
        fileMenu.addItem(NSMenuItem.separator())
        let reveal = NSMenuItem(title: "Finder で表示",
                                action: #selector(MainWindowController.revealInFinder(_:)),
                                keyEquivalent: "R")
        reveal.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(reveal)
        let trash = NSMenuItem(title: "ゴミ箱に入れる",
                               action: #selector(MainWindowController.trashSelection(_:)),
                               keyEquivalent: "\u{08}")
        trash.keyEquivalentModifierMask = []   // Photos と同じく ⌫ 単独
        fileMenu.addItem(trash)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "閉じる",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        // Edit menu
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "コピー",
                         action: #selector(MainWindowController.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "すべてを選択",
                         action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "表示")
        let sortItem = NSMenuItem(title: "並び替え", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: "並び替え")
        for (title, order) in [("新しい順", SortOrder.dateDesc),
                               ("古い順", SortOrder.dateAsc),
                               ("名前順", SortOrder.name)] {
            let mi = NSMenuItem(title: title,
                                action: #selector(MainWindowController.changeSort(_:)),
                                keyEquivalent: "")
            mi.tag = order.rawValue
            sortMenu.addItem(mi)
        }
        sortItem.submenu = sortMenu
        viewMenu.addItem(sortItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "サムネイルを大きく",
                         action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "サムネイルを小さく",
                         action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(NSMenuItem.separator())
        let sidebar = NSMenuItem(title: "サイドバーを表示/非表示",
                                 action: #selector(NSSplitViewController.toggleSidebar(_:)),
                                 keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(sidebar)
        viewItem.submenu = viewMenu

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "ウインドウ")
        windowMenu.addItem(withTitle: "しまう",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "拡大/縮小",
                           action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        windowItem.submenu = windowMenu

        return mainMenu
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
