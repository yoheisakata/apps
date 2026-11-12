// MyGallery — Photos.app 風のローカルフォルダ・ギャラリー(取り込みなし)。
//
// ルートフォルダ配下の画像を再帰スキャンし、
//   サイドバー(フォルダツリー) + サムネイルグリッド + フルサイズビューア
// で閲覧・整理する。ファイルはコピーもインポートもしない — 見るのは常に実ファイル。
//
// 単一ファイルの AppKit アプリ(WKWebView なし、依存なし、実行時ネットワークなし)。

import AppKit
import ImageIO
import CryptoKit
import CoreImage
import Vision
import AVFoundation
import AVKit

// MARK: - Configuration

/// ImageIO でデコードできる代表的な画像拡張子(RAW 含む)。
private let imageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "heic", "heif", "webp",
    "tif", "tiff", "bmp", "jp2", "avif",
    "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf",
]

/// AVFoundation が確実に再生・フレーム抽出できるコンテナに絞る(mkv/webm 等は
/// macOS 標準の AVFoundation では非対応のことが多いため含めない)。
private let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

private let browsableExtensions = imageExtensions.union(videoExtensions)

private let defaultsRootKey = "rootPath"
private let defaultsSortKey = "sortOrder"
private let defaultsCellKey = "cellSize"
private let defaultsDateBadgeKey = "showDateBadge"
private let defaultsSizeBadgeKey = "showSizeBadge"
private let defaultsAutoplayNextKey = "autoplayNextVideo"

private let minCellSize: CGFloat = 96
private let maxCellSize: CGFloat = 320
private let defaultCellSize: CGFloat = 160

enum SortOrder: Int {
    case dateDesc = 0    // 新しい順(既定)
    case dateAsc = 1     // 古い順
    case name = 2        // 名前順
    case sizeDesc = 3    // 大きい順
    case sizeAsc = 4     // 小さい順
    case qualityDesc = 5 // 画質が良い順
    case qualityAsc = 6  // 画質が悪い順(ブレ・ピンボケの抽出用)

    var showsFileSize: Bool { self == .sizeDesc || self == .sizeAsc }
    var showsQuality: Bool { self == .qualityDesc || self == .qualityAsc }
    /// 年月ごとのグリッド区切り線(`GridViewController.groupingEnabled`)は、この順序
    /// のときだけ意味を持つ ― 名前順/サイズ順/画質順で並んでいるときに日付で
    /// グルーピングしても表示順とグループが噛み合わないため(2026-09-07追加)。
    var isDateOrder: Bool { self == .dateDesc || self == .dateAsc }
}

/// メニューとツールバーの並び替えボタン(ポップオーバー)の両方が参照する共通の並び順一覧。
let sortMenuEntries: [(title: String, order: SortOrder)] = [
    ("新しい順", .dateDesc),
    ("古い順", .dateAsc),
    ("名前順", .name),
    ("サイズが大きい順", .sizeDesc),
    ("サイズが小さい順", .sizeAsc),
    ("画質が良い順", .qualityDesc),
    ("画質が悪い順(ブレの抽出)", .qualityAsc),
]

// MARK: - Model

struct PhotoItem: Equatable {
    /// ローカルファイルURL。`CGImageSourceCreateWithURL`/`AVPlayer`にそのまま渡せる。
    let url: URL
    let mtime: Date
    let fileSize: Int64
    let isVideo: Bool
    /// 元のファイル名(`url.lastPathComponent`)。
    let name: String

    init(url: URL, mtime: Date, fileSize: Int64, isVideo: Bool) {
        self.url = url
        self.mtime = mtime
        self.fileSize = fileSize
        self.isVideo = isVideo
        self.name = url.lastPathComponent
    }

    /// サムネイル/フルサイズキャッシュ・識別用の安定キー(ローカルファイルのパス)。
    var cacheKey: String { url.path }

    /// 「新しい順/古い順」で実際に使う日時。ファイル名から`FilenameDateParser`で
    /// 撮影日時(`YYYYMMDD[_HHMMSS]`パターン)を拾えればそちらを、拾えなければ
    /// `mtime`をそのまま使う(2026-09-07、ユーザー要望「デフォルトの並び順は
    /// 日付時間順にしてほしい(mtimeではなくファイル名の日付時刻で)」への対応)。
    /// `mtime`はOneDriveだとアップロード/同期日時であって撮影日時ではないことが
    /// 多く、ローカルでもコピー・バックアップ経由で変わりうるため、ファイル名に
    /// 埋め込まれた撮影日時の方が信頼できるという判断 ― サムネイルの月日バッジ・
    /// 動画再生中の日付表示・スライドショーの日付ラベルと同じ考え方。
    var sortDate: Date { FilenameDateParser.dateTime(from: name) ?? mtime }

    static func == (a: PhotoItem, b: PhotoItem) -> Bool { a.cacheKey == b.cacheKey }
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
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            if let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let u as URL in e {
                    guard browsableExtensions.contains(u.pathExtension.lowercased()) else { continue }
                    // "._IMG_0001.MOV"のようなAppleDoubleファイル(Finder経由のコピー/
                    // 外部ボリューム同期時にmacOSが自動生成する隠しファイル)を明示的に
                    // 除外する ― `.skipsHiddenFiles`はUF_HIDDENフラグベースで、
                    // SMB/NAS/外部ボリューム等ではドットファイルにこのフラグが立たない
                    // ことがあり取りこぼす(2026-09-07、実機でAppleDoubleの動画ファイルが
                    // グリッドに表示される不具合を確認して発覚)。OneDriveの
                    // `OneDriveMediaClient.makeMediaItem`側は元々同じ理由で名前ベースの
                    // 明示チェックをしていたので、ローカル側もそれに合わせた。
                    guard !u.lastPathComponent.hasPrefix(".") else { continue }
                    guard let rv = try? u.resourceValues(forKeys: keys), rv.isRegularFile == true
                    else { continue }
                    items.append(PhotoItem(url: u.standardizedFileURL,
                                           mtime: rv.contentModificationDate ?? .distantPast,
                                           fileSize: Int64(rv.fileSize ?? 0),
                                           isVideo: videoExtensions.contains(u.pathExtension.lowercased())))
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

    /// ローテーション保存などでファイル内容を書き換えた後、その1枚の mtime だけを
    /// ディスクから再取得する(フォルダ構成は変わらないので再スキャンは不要)。
    func refreshMtime(at path: String) {
        guard let idx = photos.firstIndex(where: { $0.url.path == path }) else { return }
        guard let rv = try? photos[idx].url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return }
        photos[idx] = PhotoItem(url: photos[idx].url,
                                mtime: rv.contentModificationDate ?? photos[idx].mtime,
                                fileSize: Int64(rv.fileSize ?? Int(photos[idx].fileSize)),
                                isVideo: photos[idx].isVideo)
    }

    /// サイドバーでチェックされたフォルダ群の写真の和集合。パスは常にルート配下の
    /// ディレクトリなので、`path + "/"` を前置詞に持つ写真を集めれば十分(ルート自身が
    /// チェックされている場合も同じ判定で「すべて」になる)。
    func photos(checkedPaths: Set<String>, order: SortOrder) -> [PhotoItem] {
        var list: [PhotoItem]
        if checkedPaths.isEmpty {
            list = []
        } else {
            list = photos.filter { item in
                checkedPaths.contains { item.url.path.hasPrefix($0 + "/") }
            }
        }
        switch order {
        case .name:
            list.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        case .dateDesc:
            list.sort { $0.sortDate > $1.sortDate }
        case .dateAsc:
            list.sort { $0.sortDate < $1.sortDate }
        case .sizeDesc:
            list.sort { $0.fileSize > $1.fileSize }
        case .sizeAsc:
            list.sort { $0.fileSize < $1.fileSize }
        case .qualityDesc, .qualityAsc:
            break   // 画質スコアは非同期解析が要るので MainWindowController 側で解析後に並び替える
        }
        return list
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
        let dir = base.appendingPathComponent("com.yosakata.mygallery/thumbs", isDirectory: true)
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

    func cached(_ item: PhotoItem) -> NSImage? {
        cache.object(forKey: item.cacheKey as NSString)
    }

    /// ファイル内容を書き換えた後、メモリキャッシュの古いサムネイルを追い出す
    /// (ディスクキャッシュは mtime をキーに含むので新しい mtime で自動的に再生成される)。
    func invalidate(_ item: PhotoItem) {
        cache.removeObject(forKey: item.cacheKey as NSString)
    }

    /// mtime も鍵に含めるので、ファイルが更新されればディスクキャッシュは自動的に無効化される。
    func request(_ item: PhotoItem, completion: @escaping (String, NSImage?) -> Void) {
        let key = item.cacheKey
        let mtime = item.mtime
        let url = item.url
        let isVideo = item.isVideo
        if let img = cache.object(forKey: key as NSString) { completion(key, img); return }
        if waiters[key] != nil {
            waiters[key]!.append { completion(key, $0) }
            return
        }
        waiters[key] = [{ completion(key, $0) }]
        queue.addOperation { [weak self] in
            guard let self = self else { return }
            let diskURL = ThumbnailLoader.diskCacheURL(for: key, mtime: mtime)
            var img: NSImage?
            if let cg = ThumbnailLoader.loadDiskCG(diskURL) {
                img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                ThumbnailLoader.touch(diskURL)
            } else if let cg = ThumbnailLoader.generateCG(url: url, isVideo: isVideo, maxPixel: ThumbnailLoader.gridMaxPixel) {
                img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                ThumbnailLoader.writeDiskCG(cg, to: diskURL)
            }
            DispatchQueue.main.async {
                if let img = img { self.cache.setObject(img, forKey: key as NSString) }
                for cb in self.waiters.removeValue(forKey: key) ?? [] { cb(img) }
            }
        }
    }

    static func generate(url: URL, isVideo: Bool, maxPixel: CGFloat) -> NSImage? {
        guard let cg = generateCG(url: url, isVideo: isVideo, maxPixel: maxPixel) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func generateCG(url: URL, isVideo: Bool, maxPixel: CGFloat) -> CGImage? {
        if isVideo {
            return generateVideoCG(url: url, maxPixel: maxPixel)
        }
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

    /// 動画は先頭付近(長さの10%、最大1秒)のフレームを代表画像として抜き出す。
    private static func generateVideoCG(url: URL, maxPixel: CGFloat) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let duration = asset.duration.seconds
        let seconds = duration.isFinite && duration > 0 ? min(1.0, duration * 0.1) : 0
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        return try? generator.copyCGImage(at: time, actualTime: nil)
    }

    // MARK: disk cache

    private static func diskCacheURL(for cacheKey: String, mtime: Date) -> URL {
        let raw = "\(cacheKey)|\(mtime.timeIntervalSince1970)"
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

// MARK: - Photo rotation (in-place, ⌘R)

/// 元のファイルを直接上書きして 90°時計回りに回転する(EXIF の向きを画素に焼き込んでから
/// リセットするので、以後どのビューアで開いても正しい向きで表示される)。ゴミ箱と違って
/// 元に戻せない直接上書きのため、CGImageDestination が書き込みに対応した形式(JPEG/PNG/
/// HEIC/TIFF 等)だけを対象にし、書き込み非対応の RAW 等は事前チェックで弾く。
enum PhotoRotator {
    enum RotateError: Error {
        case unsupportedFormat
        case decodeFailed
        case writeFailed

        var message: String {
            switch self {
            case .unsupportedFormat: return "この形式の保存には対応していません(RAW など)"
            case .decodeFailed: return "画像を読み込めませんでした"
            case .writeFailed: return "書き込みに失敗しました"
            }
        }
    }

    static func rotateClockwise(url: URL) -> Result<Void, RotateError> {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(src)
        else { return .failure(.decodeFailed) }

        let writableTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard writableTypes.contains(uti as String) else { return .failure(.unsupportedFormat) }

        // ダウンサンプルされないよう実寸以上の maxPixel を渡し、EXIF の向きを画素に反映させる。
        var maxSide = 8192
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            maxSide = max(maxSide, w, h)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let rotated = rotatedClockwise(oriented)
        else { return .failure(.decodeFailed) }

        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".rotate-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
        guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, uti, 1, nil) else {
            return .failure(.unsupportedFormat)
        }
        // 向きは画素側に焼き込み済みなので、書き出す EXIF の Orientation は 1(正立)にリセットする。
        CGImageDestinationAddImage(dest, rotated, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tmpURL)
            return .failure(.writeFailed)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            return .success(())
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            return .failure(.writeFailed)
        }
    }

    private static func rotatedClockwise(_ cg: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: cg).transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        let normalized = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        return CIContext(options: nil).createCGImage(normalized, from: normalized.extent)
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
    private let sizeLabel = NSTextField(labelWithString: "")
    /// 月日バッジ(2026-09-07、ファイルサイズ表示トグル追加に合わせて左上へ移動 ―
    /// 「ファイルサイズと重ならないように」というユーザー要望への対応。ファイル
    /// サイズ/画質バッジ(`sizeLabel`)は右下のまま、日付だけ独立して左上に置くことで
    /// 両方を同時に表示できるようにした)。
    private let dateLabel = NSTextField(labelWithString: "")
    private let videoIcon = NSImageView()
    private var currentPath: String?

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 5
        v.layer?.masksToBounds = true
        fill.frame = v.bounds
        fill.autoresizingMask = [.width, .height]
        v.addSubview(fill)

        sizeLabel.textColor = .white
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.wantsLayer = true
        sizeLabel.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        sizeLabel.layer?.cornerRadius = 7
        sizeLabel.isHidden = true
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(sizeLabel)

        dateLabel.textColor = .white
        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.wantsLayer = true
        dateLabel.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        dateLabel.layer?.cornerRadius = 7
        dateLabel.isHidden = true
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(dateLabel)

        videoIcon.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
        videoIcon.contentTintColor = .white
        videoIcon.wantsLayer = true
        videoIcon.layer?.shadowColor = NSColor.black.cgColor
        videoIcon.layer?.shadowOpacity = 0.6
        videoIcon.layer?.shadowRadius = 2
        videoIcon.layer?.shadowOffset = .zero
        videoIcon.isHidden = true
        videoIcon.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(videoIcon)

        NSLayoutConstraint.activate([
            sizeLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -5),
            sizeLabel.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -5),
            dateLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 5),
            dateLabel.topAnchor.constraint(equalTo: v.topAnchor, constant: 5),
            videoIcon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
            videoIcon.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6),
            videoIcon.widthAnchor.constraint(equalToConstant: 20),
            videoIcon.heightAnchor.constraint(equalToConstant: 20),
        ])
        view = v
    }

    func configure(with photo: PhotoItem, badgeText: String?, dateText: String?) {
        currentPath = photo.cacheKey
        view.toolTip = photo.name
        sizeLabel.isHidden = (badgeText == nil)
        if let badgeText {
            sizeLabel.stringValue = "  \(badgeText)  "
        }
        dateLabel.isHidden = (dateText == nil)
        if let dateText {
            dateLabel.stringValue = "  \(dateText)  "
        }
        videoIcon.isHidden = !photo.isVideo
        if let img = ThumbnailLoader.shared.cached(photo) {
            fill.image = img
            return
        }
        fill.image = nil
        ThumbnailLoader.shared.request(photo) { [weak self] key, img in
            guard let self = self, self.currentPath == key else { return }
            self.fill.image = img
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentPath = nil
        fill.image = nil
        view.toolTip = nil
        sizeLabel.isHidden = true
        dateLabel.isHidden = true
        videoIcon.isHidden = true
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

    /// 年月グループのセクション分割(`GridViewController`の区切り線表示、2026-09-07)
    /// があっても、このクラスのキーボード/クリックの選択ロジックは「`items`という
    /// 1本のフラットな配列」を前提にしたまま保つ ― 実際の(セクション付き)
    /// `IndexPath`との相互変換はこれらのクロージャに委ねる(`GridViewController
    /// .loadView()`が注入する)。未設定時はセクション0前提のフォールバックになる。
    var totalItemCount: (() -> Int)?
    var indexPathForFlatIndex: ((Int) -> IndexPath)?
    var flatIndexForIndexPath: ((IndexPath) -> Int)?

    /// ⇧←/⇧→ 範囲選択の起点(anchor)と現在位置(focus)。直前に単独クリックした
    /// アイテムや `resetKeyboardAnchor(to:)` の呼び出しで更新される。`items`上の
    /// フラットなインデックスで保持する(上記の理由)。
    private var keyboardAnchor: Int?
    private var keyboardFocus: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func flat(_ ip: IndexPath) -> Int { flatIndexForIndexPath?(ip) ?? ip.item }
    private func indexPath(_ flat: Int) -> IndexPath { indexPathForFlatIndex?(flat) ?? IndexPath(item: flat, section: 0) }

    // ⌘クリック(個別トグル)とドラッグ開始は NSCollectionView 標準の mouseDown に任せる。
    // ただし⇧クリックの範囲選択は NSCollectionView が自前実装しないと効かないため、
    // ここで明示的に処理する(起点は直前の単独クリック、なければ現在の選択の先頭)。
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let ip = indexPathForItem(at: pt)
        let flatIdx = ip.map { flat($0) }

        if event.clickCount == 2, let flatIdx {
            onOpen?(flatIdx)
            return
        }

        if event.modifierFlags.contains(.shift), let flatIdx {
            let anchor = keyboardAnchor ?? selectionIndexPaths.sorted().first.map { flat($0) } ?? flatIdx
            keyboardAnchor = anchor
            keyboardFocus = flatIdx
            let lo = min(anchor, flatIdx)
            let hi = max(anchor, flatIdx)
            let range = Set((lo...hi).map { indexPath($0) })
            selectItems(at: range, scrollPosition: [])
            deselectItems(at: Set(selectionIndexPaths).subtracting(range))
            onSelectionChanged?()
            return
        }

        super.mouseDown(with: event)
        guard let flatIdx else {
            if event.modifierFlags.intersection([.shift, .command]).isEmpty {
                keyboardAnchor = nil
                keyboardFocus = nil
            }
            return
        }
        if event.modifierFlags.intersection([.shift, .command]).isEmpty {
            keyboardAnchor = flatIdx
            keyboardFocus = flatIdx
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76:   // Return / Space / Enter → ビューアを開く
            if let ip = selectionIndexPaths.sorted().first {
                onOpen?(flat(ip))
            } else {
                super.keyDown(with: event)
            }
        // ⇧← / ⇧↑ → 選択範囲を伸縮(where は各パターンに個別に効くため両方に付ける)
        case 123 where event.modifierFlags.contains(.shift),
             126 where event.modifierFlags.contains(.shift):
            extendSelection(by: -1)
        // ⇧→ / ⇧↓ → 選択範囲を伸縮
        case 124 where event.modifierFlags.contains(.shift),
             125 where event.modifierFlags.contains(.shift):
            extendSelection(by: 1)
        default:
            super.keyDown(with: event)
        }
    }

    /// フォルダ切替・ソート変更・トラッシュ後の再選択など、選択が外部要因で変わったときに
    /// ⇧←/⇧→ 範囲選択の起点をリセットする。`flatIndex`は`items`上のインデックス。
    func resetKeyboardAnchor(to flatIndex: Int?) {
        keyboardAnchor = flatIndex
        keyboardFocus = flatIndex
    }

    /// 直前に単独クリックした(または resetKeyboardAnchor で指定された)アイテムを起点に、
    /// 選択範囲を1件ずつ伸縮する(Finder のリスト表示と同じ操作感)。
    private func extendSelection(by delta: Int) {
        let total = totalItemCount?() ?? numberOfItems(inSection: 0)
        guard total > 0 else { return }
        let anchor = keyboardAnchor ?? selectionIndexPaths.sorted().first.map { flat($0) } ?? 0
        keyboardAnchor = anchor
        let focus = keyboardFocus ?? anchor
        let nextItem = max(0, min(total - 1, focus + delta))
        keyboardFocus = nextItem

        let lo = min(anchor, nextItem)
        let hi = max(anchor, nextItem)
        let range = Set((lo...hi).map { indexPath($0) })
        selectItems(at: range, scrollPosition: [])
        deselectItems(at: Set(selectionIndexPaths).subtracting(range))
        scrollToItems(at: [indexPath(nextItem)], scrollPosition: .nearestHorizontalEdge)
        onSelectionChanged?()
    }

    /// ⌘A ですべて選択する(NSCollectionView は selectAll(_:) を自前実装しないと効かないため)。
    override func selectAll(_ sender: Any?) {
        let total = totalItemCount?() ?? numberOfItems(inSection: 0)
        guard total > 0 else { return }
        selectItems(at: Set((0..<total).map { indexPath($0) }), scrollPosition: [])
        onSelectionChanged?()
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

/// グリッド全体(空状態のメッセージ表示も含む)を覆うコンテナ用のドロップ受け皿。
/// `NSCollectionView`は0件のときレイアウトの content size がほぼゼロになりフレームが
/// 収縮するため、`GridCollectionView`自身へのドラッグ登録だけでは「フォルダが空/未選択の
/// 状態でウインドウにドロップしても反応しない」問題が起きる(ドラッグの着地判定は
/// hit-test で最も深い登録済みビューを探すため、収縮したコレクションビューの外側に
/// カーソルがあると見つからない)。グリッドの外枠である`root`ビュー自体もここで
/// ドロップ登録することで、空状態でも常にウインドウ全体がドロップを受け付ける。
final class FolderDropView: NSView {
    var onDropFolder: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

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
            recomputeGroups()
            collectionView.reloadData()
            // 保険として可視セルも直接歩いて再構成する ― `refreshVisibleBadges()`の
            // コメント参照(2026-09-07、OneDriveタブでのバッジ不具合対策)。OneDriveは
            // フェーズ2のたびに`items`を何度も再代入するため、この経路(`items`が
            // 変わるたび)が実際に問題を踏んでいた本命の箇所。
            refreshVisibleBadges()
            collectionView.resetKeyboardAnchor(to: nil)
            collectionView.onSelectionChanged?()
        }
    }

    // MARK: - 年月グループ(グリッドの区切り線)

    /// 「サムネイル一覧に年月ごとの区切り線を表示できないか」というユーザー要望への
    /// 対応(2026-09-07)。`NSCollectionViewFlowLayout`のセクション機能を使う ―
    /// セクションが変わると自動的に改行される(同じ行に前グループの残りが混ざらない)
    /// ため、区切り線を各セクションのヘッダーとして描く。**キーボード操作・選択・
    /// ドラッグ&ドロップ・ビューアの「次へ/前へ」は、このセクション分割の影響を
    /// 一切受けない**よう設計した ― `items`(フラットな1本の配列)が唯一の真実の
    /// 順序で、セクションは`items`から`recomputeGroups()`が導出する表示上の区切りに
    /// すぎない。`MainWindowController`側(`viewerIndex`等)は`gridVC.items`を
    /// そのままフラットなインデックスで扱い続けており、変更不要。`GridCollectionView`
    /// のキーボード/クリック処理だけは実際の(セクション付き)`IndexPath`を扱う必要が
    /// あるため、`flatIndex(for:)`/`indexPath(forFlatIndex:)`という相互変換を注入して
    /// いる(下記`loadView()`のクロージャ配線を参照)。
    private struct DateGroup {
        let title: String
        let items: [PhotoItem]
    }

    /// `sortOrder`が日付順(新しい順/古い順)のときだけ`true`にする
    /// (`MainWindowController`が`sortOrder`のdidSetから設定する)。日付順以外では
    /// グルーピングしても表示順と噛み合わないため、常に1グループ(見た目は従来通り
    /// フラット、ヘッダーも出さない)に固定する。
    var groupingEnabled = true {
        didSet {
            guard groupingEnabled != oldValue else { return }
            recomputeGroups()
            collectionView.reloadData()
        }
    }

    private var groups: [DateGroup] = []

    private static let groupTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f
    }()

    /// `items`(現在の表示順のまま)を年月の変わり目で連続run分割する。`sortDate`
    /// (`PhotoItem.sortDate`、ファイル名優先の撮影日時)を使う ― 表示順に使っている
    /// ソートキーと同じ基準でグルーピングしないと境界がずれる。
    private func recomputeGroups() {
        defer {
            // ヘッダー(区切り線)の高さはグルーピング無効/1グループ以下のときは0にして
            // 消す ― 名前順/サイズ順等では常にフラット表示(従来通り)に戻す。
            layout.headerReferenceSize = (groupingEnabled && groups.count > 1)
                ? NSSize(width: 0, height: 32) : .zero
        }
        guard groupingEnabled, !items.isEmpty else {
            groups = items.isEmpty ? [] : [DateGroup(title: "", items: items)]
            return
        }
        let cal = Calendar(identifier: .gregorian)
        var result: [DateGroup] = []
        var currentKey: DateComponents?
        var currentItems: [PhotoItem] = []
        for item in items {
            let key = cal.dateComponents([.year, .month], from: item.sortDate)
            if key != currentKey {
                if let currentKey, !currentItems.isEmpty {
                    result.append(DateGroup(title: Self.title(for: currentKey), items: currentItems))
                }
                currentKey = key
                currentItems = [item]
            } else {
                currentItems.append(item)
            }
        }
        if let currentKey, !currentItems.isEmpty {
            result.append(DateGroup(title: Self.title(for: currentKey), items: currentItems))
        }
        groups = result
    }

    private static func title(for key: DateComponents) -> String {
        guard let year = key.year, let month = key.month else { return "" }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: comps) else { return "" }
        return groupTitleFormatter.string(from: date)
    }

    /// (セクション, アイテム)の実際の`IndexPath` → `items`上のフラットなインデックス。
    private func flatIndex(for indexPath: IndexPath) -> Int {
        guard indexPath.section < groups.count else { return indexPath.item }
        var idx = 0
        for s in 0..<indexPath.section { idx += groups[s].items.count }
        return idx + indexPath.item
    }

    /// `items`上のフラットなインデックス → 実際の(セクション, アイテム)`IndexPath`。
    private func indexPath(forFlatIndex flat: Int) -> IndexPath {
        var remaining = max(flat, 0)
        for (s, g) in groups.enumerated() {
            if remaining < g.items.count { return IndexPath(item: remaining, section: s) }
            remaining -= g.items.count
        }
        let lastSection = max(groups.count - 1, 0)
        return IndexPath(item: max((groups.last?.items.count ?? 1) - 1, 0), section: lastSection)
    }

    var cellSize: CGFloat = defaultCellSize {
        didSet {
            layout.itemSize = NSSize(width: cellSize, height: cellSize)
            layout.invalidateLayout()
        }
    }

    /// 右下バッジ(サイズ/画質、排他 ― どちらか一方しか意味を持たないので1スロット)。
    /// 月日バッジ(左上)は`showDateBadge`という別スロットで独立している
    /// (2026-09-07、「ファイルサイズと月日が重ならないように」というユーザー要望で
    /// 左上/右下の2スロットに分離した ― 以前は`.date`もこの同じenumの1ケースで
    /// 右下バッジと排他だった)。
    enum ThumbnailBadge { case none, fileSize, quality }

    var thumbnailBadge: ThumbnailBadge = .none {
        didSet {
            guard thumbnailBadge != oldValue else { return }
            collectionView.reloadData()
            refreshVisibleBadges()
        }
    }

    /// 左上の月日バッジを表示するかどうか。右下の`thumbnailBadge`(サイズ/画質)とは
    /// 独立に、`MainWindowController`が「月日を表示」トグルで制御する。
    var showDateBadge = false {
        didSet {
            guard showDateBadge != oldValue else { return }
            collectionView.reloadData()
            refreshVisibleBadges()
        }
    }

    /// `reloadData()`だけでは既存のインデックスパスに対応する画面上のセルが
    /// 再構成されない(＝バッジの新しい状態が反映されない)ケースへの保険
    /// (2026-09-07、「起動時、月日トグルはONなのに表示されない。手動でOFF→ONし
    /// 直すと出る」というユーザー報告への対応)。OneDriveタブはフェーズ2のたびに
    /// `items`を(既存の要素インデックスを保ったまま件数だけ増やして)何度も
    /// 再代入するため、`reloadData()`が既存インデックスパスのセルビューを使い回して
    /// `itemForRepresentedObjectAt`を呼び直さない――というAppKit側の挙動に
    /// 遭遇した可能性がある(ローカルは1回の代入で完結するため症状が出なかったと
    /// 推測)。原因の完全な特定はできていないが、`reloadData()`に加えて**現在画面に
    /// 見えているセルを直接歩いて明示的に`configure`し直す**ことで、この経路に
    /// 依存せず確実にバッジ状態を反映させる。
    private func refreshVisibleBadges() {
        for case let cell as PhotoCell in collectionView.visibleItems() {
            guard let indexPath = collectionView.indexPath(for: cell),
                  indexPath.section < groups.count, indexPath.item < groups[indexPath.section].items.count
            else { continue }
            configure(cell, at: indexPath)
        }
    }

    /// `.quality` バッジ表示時にスコアを取得するクロージャ(`MainWindowController`が
    /// `QualityCache.result(for:)` を渡す)。未解析なら nil。
    var qualityScoreProvider: ((PhotoItem) -> Double?)?

    /// 月日バッジの表示形式。`"Jan 1"`のような英語の月名+日(2026-09-07、ユーザー要望
    /// 「1/1じゃなくてJan 1みたいにして」への対応 ― 以前は`"M/d"`だった)。
    /// システムのロケールがどうであれ英語表記になるよう`locale`を明示している
    /// (このアプリ自体は全編日本語UIだが、日付バッジだけは意図的に英語表記)。
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    /// 月日バッジの表示文字列(2026-09-07追加、ユーザー要望「サムネに月日を表示
    /// できる?」への対応)。`FilenameDateParser`(ファイル名から`YYYYMMDD`パターンを
    /// 拾う、元は動画再生中の日付表示・スライドショー用)をまず試し、拾えなければ
    /// `photo.mtime`にフォールバックする ― OneDriveの更新日時はアップロード/同期日時で
    /// あって撮影日ではないことが多い(`FilenameDateParser`のコメント参照)ため、
    /// ファイル名から取れるならそちらを優先する。
    private static func monthDayText(for photo: PhotoItem) -> String {
        let date = FilenameDateParser.date(from: photo.name) ?? photo.mtime
        return monthDayFormatter.string(from: date)
    }

    override func loadView() {
        let root = FolderDropView()
        root.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        root.onDropFolder = { [weak self] url in self?.collectionView.onDropFolder?(url) }

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
        collectionView.register(DateSectionHeaderView.self,
                                 forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                 withIdentifier: Self.headerID)
        // キーボード/クリックの選択ロジックは`items`のフラットなインデックスで考えたい
        // (年月グループのセクション分割はあくまで表示上の区切りのため) ― 実際の
        // `IndexPath`との相互変換を`GridCollectionView`へ注入する(`recomputeGroups()`
        // 直上のコメント参照)。
        collectionView.totalItemCount = { [weak self] in self?.items.count ?? 0 }
        collectionView.indexPathForFlatIndex = { [weak self] flat in
            self?.indexPath(forFlatIndex: flat) ?? IndexPath(item: flat, section: 0)
        }
        collectionView.flatIndexForIndexPath = { [weak self] ip in self?.flatIndex(for: ip) ?? ip.item }

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
        collectionView.selectionIndexPaths.sorted().compactMap { ip in
            guard ip.section < groups.count, ip.item < groups[ip.section].items.count else { return nil }
            return groups[ip.section].items[ip.item]
        }
    }

    /// 現在選択されている先頭アイテムの`items`上のフラットなインデックス(無選択ならnil)。
    /// `MainWindowController.startSlideshow`が選択範囲の先頭から始めるために使う ―
    /// セクション分割(年月区切り線)の影響を受けないよう、実際の`IndexPath`ではなく
    /// これを介する。
    var firstSelectedIndex: Int? {
        guard let ip = collectionView.selectionIndexPaths.sorted().first else { return nil }
        return flatIndex(for: ip)
    }

    /// `index`は`items`(フラットな配列)上のインデックス ― 呼び出し元
    /// (`MainWindowController`)はセクション分割を意識しない。
    func select(index: Int) {
        guard index >= 0, index < items.count else { return }
        let ip = indexPath(forFlatIndex: index)
        collectionView.deselectAll(nil)
        collectionView.selectItems(at: [ip], scrollPosition: .nearestHorizontalEdge)
        collectionView.resetKeyboardAnchor(to: index)
        collectionView.onSelectionChanged?()
    }

    // MARK: data source

    func numberOfSections(in cv: NSCollectionView) -> Int { groups.count }

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section < groups.count else { return 0 }
        return groups[section].items.count
    }

    func collectionView(_ cv: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = cv.makeItem(withIdentifier: PhotoCell.reuseID, for: indexPath) as! PhotoCell
        configure(cell, at: indexPath)
        return cell
    }

    /// `itemForRepresentedObjectAt`と`refreshVisibleBadges`(上記)の両方から呼ぶ
    /// 共通のバッジ計算+反映ロジック。
    private func configure(_ cell: PhotoCell, at indexPath: IndexPath) {
        guard indexPath.section < groups.count, indexPath.item < groups[indexPath.section].items.count else { return }
        let photo = groups[indexPath.section].items[indexPath.item]
        let badgeText: String?
        switch thumbnailBadge {
        case .none: badgeText = nil
        case .fileSize: badgeText = formatBytes(photo.fileSize)
        case .quality:
            badgeText = qualityScoreProvider?(photo).map { String(format: "%.0f", $0) } ?? "…"
        }
        let dateText = showDateBadge ? Self.monthDayText(for: photo) : nil
        cell.configure(with: photo, badgeText: badgeText, dateText: dateText)
    }

    private static let headerID = NSUserInterfaceItemIdentifier("DateSectionHeader")

    func collectionView(_ cv: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let header = cv.makeSupplementaryView(ofKind: kind, withIdentifier: Self.headerID, for: indexPath) as! DateSectionHeaderView
        header.setTitle(indexPath.section < groups.count ? groups[indexPath.section].title : "")
        return header
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
        guard indexPath.section < groups.count, indexPath.item < groups[indexPath.section].items.count else { return nil }
        return groups[indexPath.section].items[indexPath.item].url as NSURL
    }
}

/// 年月グループの見出し(セクションヘッダー) ― タイトルラベル+下端の水平線
/// (`NSBox`の`.separator`)。「年、月ごとに水平線みたいなものを表示できない?」
/// というユーザー要望への対応(2026-09-07)。
final class DateSectionHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let line = NSBox()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            line.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ text: String) { label.stringValue = text }
}

// MARK: - Sidebar

/// フォルダ行のチェックボックス。再利用されるセルからどの FolderNode に対応するか
/// 引けるよう、node を直接持たせる(NSOutlineView は行の再利用でセルを使い回すため)。
private final class SidebarCheckbox: NSButton {
    weak var node: FolderNode?
}

private final class SidebarCellView: NSTableCellView {
    var checkbox: SidebarCheckbox!
}

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let outline = NSOutlineView()
    /// チェック状態(=表示に含めるフォルダ)が変わるたびに呼ばれる。
    var onCheckedChanged: (() -> Void)?

    private(set) var rootNode: FolderNode?
    /// チェック済みフォルダのパス集合。複数チェックした場合はその和集合の写真を表示する。
    private(set) var checkedPaths: Set<String> = []
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
        outline.selectionHighlightStyle = .none   // 選択ではなくチェックボックスで絞り込む
        outline.dataSource = self
        outline.delegate = self
        outline.autoresizesOutlineColumn = true

        scroll.documentView = outline
        view = scroll
    }

    /// カラム幅をサイドバーの実サイズへ追従させる ― `GallerySettings.swift`の
    /// `NSOutlineView.syncSingleColumnWidthToBounds()`参照。
    override func viewDidLayout() {
        super.viewDidLayout()
        outline.syncSingleColumnWidthToBounds()
    }

    /// ツリーを差し替える。チェック状態は新しいツリーにも同じパスが残っていれば引き継ぎ、
    /// 何も残らなければ(新しいルートを開いた直後など)ルート = すべての写真をチェックする。
    func setRoot(_ node: FolderNode?) {
        rootNode = node
        guard let root = node else {
            checkedPaths = []
            outline.reloadData()
            return
        }
        checkedPaths.formIntersection(allPaths(in: root))
        if checkedPaths.isEmpty { checkedPaths = allPaths(in: root) }
        outline.reloadData()
        outline.expandItem(root)
    }

    private func allPaths(in node: FolderNode) -> Set<String> {
        var s: Set<String> = [node.url.path]
        for c in node.children { s.formUnion(allPaths(in: c)) }
        return s
    }

    /// このノード自身、またはその祖先のいずれかがチェック済みか(グリッド側のフィルタ
    /// `PhotoStore.photos(checkedPaths:order:)` は「チェック済みパスのいずれかが祖先なら
    /// 含める」という判定なので、それと同じ意味の判定をここでも使う)。
    private func isEffectivelyChecked(_ node: FolderNode) -> Bool {
        var n: FolderNode? = node
        while let cur = n {
            if checkedPaths.contains(cur.url.path) { return true }
            n = cur.parent
        }
        return false
    }

    /// このノード配下でチェック済み(=実際にグリッドへ表示される)写真の合計枚数。
    /// 祖先がチェック済みならこのノードの totalCount をまるごと使い、そうでなければ
    /// 子ノードのうちチェック済みのものだけを再帰的に合算する。
    private func checkedCount(in node: FolderNode) -> Int {
        if isEffectivelyChecked(node) { return node.totalCount }
        return node.children.reduce(0) { $0 + checkedCount(in: $1) }
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
        let cell = ov.makeView(withIdentifier: cellID, owner: nil) as? SidebarCellView ?? makeCell()
        let isRoot = node === rootNode
        cell.checkbox.node = node
        cell.checkbox.state = checkedPaths.contains(node.url.path) ? .on : .off
        cell.textField?.stringValue =
            (isRoot ? "すべての写真" : node.name) + " (\(checkedCount(in: node)))"
        cell.imageView?.image = NSImage(
            systemSymbolName: isRoot ? "photo.on.rectangle" : "folder",
            accessibilityDescription: nil)
        return cell
    }

    /// チェック/解除は配下のサブフォルダ全部に連動する(Finderのタグ選択などと同じ、
    /// 親を触ると子もまとめて追従するチェックボックスツリーの一般的な挙動)。
    /// 連動先のチェックボックスも見た目を更新する必要があるため reloadData する。
    @objc private func checkboxToggled(_ sender: SidebarCheckbox) {
        guard let node = sender.node else { return }
        let affected = allPaths(in: node)
        if sender.state == .on {
            checkedPaths.formUnion(affected)
        } else {
            checkedPaths.subtract(affected)
        }
        outline.reloadData()
        onCheckedChanged?()
    }

    private func makeCell() -> SidebarCellView {
        let cell = SidebarCellView()
        cell.identifier = cellID
        let checkbox = SidebarCheckbox(checkboxWithTitle: "", target: self, action: #selector(checkboxToggled(_:)))
        let iv = NSImageView()
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(checkbox)
        cell.addSubview(iv)
        cell.addSubview(tf)
        cell.checkbox = checkbox
        cell.imageView = iv
        cell.textField = tf
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
            checkbox.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 4),
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
    /// スライドショー中(`SlideshowController`が`true`にする)。Spaceキーの意味が
    /// 「写真を閉じる」から「一時停止/再開」に変わり、動画は`onVideoFinished`で
    /// 自動的に次へ進めるようになる。
    var slideshowMode = false
    /// スライドショー中、動画が最後まで再生し終わったときに呼ばれる。
    var onVideoFinished: (() -> Void)?
    /// スライドショー中、Spaceキーが押されたときに呼ばれる(一時停止/再開は
    /// `SlideshowController`が`pauseVideo()`/`resumeVideo()`経由で行う)。
    var onTogglePause: (() -> Void)?
    /// 通常視聴(スライドショーではない)中に動画の自動連続再生を有効にするか
    /// (2026-09-07追加、ユーザー要望「次の動画に自動再生、トグルボタンを作って」への
    /// 対応)。`MainWindowController`がツールバーのトグルボタンの状態を反映する。
    var autoplayNext = false
    /// `autoplayNext`が有効なとき、動画が最後まで再生し終わったら呼ばれる
    /// (`onVideoFinished`はスライドショー専用のままにして役割を分けている ―
    /// スライドショー側は一時停止状態やタイマーも絡むため、単純な「次へ進む」だけの
    /// 通常視聴とは呼び出し元の扱いが異なる)。
    var onAutoAdvance: (() -> Void)?
    /// 写真上でドラッグ選択した範囲を「璃央」として登録する(特徴量, 重複判定キー)。
    var onRegisterRio: ((VNFeaturePrintObservation, String) -> Void)?

    // 範囲選択(璃央登録)。ビューア座標(左下原点)。静止画のみ。
    private let selectionBox = NSView()
    private let registerButton = NSButton(title: "この範囲を璃央として登録", target: nil, action: nil)
    private var dragStart: NSPoint?
    private var selectionRect: NSRect?
    private var baseInfo = ""
    private var currentPhotoKey = ""

    private let imageView = FillImageView(gravity: .resizeAspect)
    private let playerView: AVPlayerView = {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = true
        return v
    }()
    private let infoLabel = NSTextField(labelWithString: "")
    private var currentPath: String?
    private var currentIsVideo = false
    private var videoEndObserver: NSObjectProtocol?
    /// 動画の再生失敗を検出するための監視(2026-09-07追加 ― 「サムネは取得できて
    /// いるファイルが再生できないときがある」というユーザー要望への対応。それまでは
    /// `AVPlayer`の失敗を一切拾っておらず、再生ボタンを押しても無音で何も起きない
    /// ように見えていた)。`statusObservation`は`AVPlayerItem.status`が`.failed`に
    /// なった場合(再生開始前に失敗、例: コーデック非対応・URL失効)、
    /// `failedToPlayObserver`は`.AVPlayerItemFailedToPlayToEndTime`通知(再生開始後に
    /// 失敗、例: ネットワーク切断)を拾う。
    private var statusObservation: NSKeyValueObservation?
    private var failedToPlayObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isHidden = true
        addSubview(playerView)

        infoLabel.textColor = .white
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.alignment = .center
        infoLabel.wantsLayer = true
        infoLabel.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        infoLabel.layer?.cornerRadius = 9
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)

        selectionBox.wantsLayer = true
        selectionBox.layer?.borderColor = NSColor.systemYellow.cgColor
        selectionBox.layer?.borderWidth = 2
        selectionBox.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.12).cgColor
        selectionBox.isHidden = true
        addSubview(selectionBox)
        registerButton.bezelStyle = .rounded
        registerButton.target = self
        registerButton.action = #selector(registerSelection)
        registerButton.keyEquivalent = ""
        registerButton.isHidden = true
        addSubview(registerButton)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            infoLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            infoLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    func show(photo: PhotoItem, index: Int, total: Int) {
        currentPath = photo.cacheKey
        currentIsVideo = photo.isVideo
        // 動画再生中はファイル名から`FilenameDateParser`(元はスライドショー専用に
        // 移植した`YYYYMMDD`パターン抽出)で撮影日らしき日付を拾って添える(2026-09-07、
        // ユーザー要望「ファイル名から年月日を出して、動画再生時に表示したい」への対応)。
        // 写真では出さない ― スライドショーの日付ラベルと役割が重複するため、通常視聴
        // ビューアでは動画だけに絞った。`photo.name`(元ファイル名)を使う ―
        // `photo.url`はOneDriveでは署名付きダウンロードURLでファイル名を反映しない。
        var info = "  \(photo.name) — \(index + 1) / \(total)  "
        if photo.isVideo, let date = FilenameDateParser.date(from: photo.name) {
            info = "  \(photo.name) — \(index + 1) / \(total) — \(Self.dateFormatter.string(from: date))  "
        }
        if !photo.isVideo { info += "— ドラッグで璃央を範囲選択  " }
        baseInfo = info
        currentPhotoKey = photo.cacheKey
        clearSelection()
        infoLabel.stringValue = info
        playerView.player?.pause()
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            videoEndObserver = nil
        }
        if let observer = failedToPlayObserver {
            NotificationCenter.default.removeObserver(observer)
            failedToPlayObserver = nil
        }
        statusObservation = nil

        if photo.isVideo {
            imageView.isHidden = true
            playerView.isHidden = false
            // スライドショー中は自前のコントロールバーだけを使い、AVKit標準の
            // コントロールと二重に持たせない(通常の手動視聴では従来通り表示する)。
            playerView.controlsStyle = slideshowMode ? .none : .floating
            let player = AVPlayer(url: photo.url)
            playerView.player = player
            player.play()
            if let item = player.currentItem {
                if slideshowMode {
                    videoEndObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                    ) { [weak self] _ in self?.onVideoFinished?() }
                } else if autoplayNext {
                    videoEndObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                    ) { [weak self] _ in self?.onAutoAdvance?() }
                }
                let path = photo.cacheKey
                let name = photo.name
                statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    DispatchQueue.main.async {
                        guard let self, self.currentPath == path else { return }
                        self.showPlaybackError(item.error, photoName: name)
                    }
                }
                failedToPlayObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
                ) { [weak self] note in
                    guard let self, self.currentPath == path else { return }
                    let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    self.showPlaybackError(error ?? item.error, photoName: name)
                }
            }
        } else {
            playerView.player = nil
            playerView.isHidden = true
            imageView.isHidden = false
            // まずグリッドのサムネイルを即表示し、裏で高解像度(最大 4096px)を読む
            imageView.image = ThumbnailLoader.shared.cached(photo)
            let url = photo.url
            let key = photo.cacheKey
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let img = ThumbnailLoader.generate(url: url, isVideo: false, maxPixel: 4096)
                DispatchQueue.main.async {
                    guard let self = self, self.currentPath == key else { return }
                    if let img = img { self.imageView.image = img }
                }
            }
        }
    }

    /// 動画の再生に失敗したときのエラー表示。`NSAlert`の本文はそのままでも選択できる
    /// ことが多いが確実ではないため、「コピー」ボタンで確実にクリップボードへ
    /// コピーできるようにしてある(2026-09-07、ユーザー要望「何のエラーが表示して
    /// コピペできるようにしてほしい」への対応)。`NSError`の場合は`userInfo`から
    /// 拾えるだけの詳細(ドメイン・コード・失敗理由)も併記する ― OneDriveの署名付き
    /// URLの期限切れ、非対応コーデック等、原因の切り分けに役立つ情報はできるだけ残す。
    private func showPlaybackError(_ error: Error?, photoName: String) {
        var lines = ["ファイル: \(photoName)"]
        if let error {
            let ns = error as NSError
            lines.append("エラー: \(ns.localizedDescription)")
            lines.append("ドメイン: \(ns.domain) (\(ns.code))")
            if let reason = ns.localizedFailureReason { lines.append("理由: \(reason)") }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                lines.append("詳細: \(underlying.localizedDescription) [\(underlying.domain) \(underlying.code)]")
            }
        } else {
            lines.append("エラー: (詳細情報なし)")
        }
        let text = lines.joined(separator: "\n")

        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "動画を再生できませんでした"
        a.informativeText = text
        a.addButton(withTitle: "コピー")
        a.addButton(withTitle: "OK")
        if a.runModal() == .alertFirstButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    /// ビューアがウインドウから外れた(閉じられた)ら、裏で音声が鳴り続けないよう再生を止める。
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            playerView.player?.pause()
            if let observer = videoEndObserver {
                NotificationCenter.default.removeObserver(observer)
                videoEndObserver = nil
            }
            if let observer = failedToPlayObserver {
                NotificationCenter.default.removeObserver(observer)
                failedToPlayObserver = nil
            }
            statusObservation = nil
        }
    }

    /// スライドショー中の一時停止/再開(`SlideshowController`から呼ばれる)。
    func pauseVideo() { playerView.player?.pause() }
    func resumeVideo() { playerView.player?.play() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:   // Esc — 範囲選択中はまず選択を解除
            if selectionRect != nil { clearSelection() } else { onClose?() }
        case 36 where selectionRect != nil:   // Return — 選択範囲を登録
            registerSelection()
        case 49:   // Space — スライドショー中は一時停止/再開、通常時は動画は誤操作で
                   // 閉じないよう無視(再生/一時停止はプレイヤーのコントロールで)。
            if slideshowMode {
                onTogglePause?()
            } else if !currentIsVideo {
                onClose?()
            }
        case 123, 126: // ← / ↑
            onStep?(-1)
        case 124, 125: // → / ↓
            onStep?(1)
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onClose?(); return }
        clearSelection()
        guard !currentIsVideo, let disp = displayedImageRect() else { return }
        let p = convert(event.locationInWindow, from: nil)
        if disp.contains(p) { dragStart = p }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let disp = displayedImageRect() else { return }
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(p.x, disp.minX), disp.maxX)
        p.y = min(max(p.y, disp.minY), disp.maxY)
        let r = NSRect(x: min(start.x, p.x), y: min(start.y, p.y),
                       width: abs(start.x - p.x), height: abs(start.y - p.y))
        selectionBox.frame = r
        selectionBox.isHidden = false
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard dragStart != nil, !selectionBox.isHidden else { return }
        let r = selectionBox.frame
        guard r.width >= 16, r.height >= 16 else { clearSelection(); return }
        selectionRect = r
        registerButton.sizeToFit()
        var origin = NSPoint(x: r.midX - registerButton.frame.width / 2, y: r.minY - registerButton.frame.height - 8)
        if origin.y < 8 { origin.y = r.maxY + 8 }
        origin.x = min(max(origin.x, 8), bounds.width - registerButton.frame.width - 8)
        registerButton.setFrameOrigin(origin)
        registerButton.isHidden = false
    }

    private func clearSelection() {
        dragStart = nil
        selectionRect = nil
        selectionBox.isHidden = true
        registerButton.isHidden = true
    }

    /// 画像がアスペクトフィットで実際に描画されている領域(ビューア座標)。
    private func displayedImageRect() -> NSRect? {
        guard let img = imageView.image, img.size.width > 0, img.size.height > 0 else { return nil }
        let b = bounds
        let sc = min(b.width / img.size.width, b.height / img.size.height)
        let w = img.size.width * sc, h = img.size.height * sc
        return NSRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
    }

    @objc private func registerSelection() {
        guard let r = selectionRect, let disp = displayedImageRect(), let img = imageView.image,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let px = CGRect(x: (r.minX - disp.minX) / disp.width * W,
                        y: (disp.maxY - r.maxY) / disp.height * H,
                        width: r.width / disp.width * W,
                        height: r.height / disp.height * H)
        let key = "\(currentPhotoKey)#\(Int(px.minX)),\(Int(px.minY)),\(Int(px.width)),\(Int(px.height))"
        clearSelection()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fp = RioFaceAnalyzer.regionPrint(cg: cg, pixelRect: px)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let fp = fp {
                    self.onRegisterRio?(fp, key)
                } else {
                    self.showToast("この範囲から特徴を取得できませんでした")
                }
            }
        }
    }

    /// infoLabelに一時メッセージを出し、2秒後に元の表示へ戻す。
    func showToast(_ text: String) {
        infoLabel.stringValue = "  \(text)  "
        let base = baseInfo
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.baseInfo == base else { return }
            self.infoLabel.stringValue = base
        }
    }
}

// MARK: - Duplicate detection
//
// 旧 myorganizer(当時 organizer/Organizer.app)の「重複写真」ペイン(DupPhotosViewModel)と
// 同等のロジック。同ペインは myorganizer から削除済みで、現在はこの実装だけが残っている:
// サイズ→SHA-256 の完全一致に加え、dHash(知覚ハッシュ)のハミング距離によるあいまい
// 一致(リサイズ/再エンコードされた「似ている」写真)を検出し、マッチレベル/残す基準を
// 切り替えられる。グループ単位の有効/無効切り替えと、1グループあたりの削除上限
// (maxDeletePerGroup、既定3枚)も同ペインに合わせて実装している — 「ゆるい」等の
// 緩いマッチレベルで誤って大きくクラスタリングされたグループを一気に削除しないための
// 安全策。

/// 完全一致(サイズ+SHA-256)か、dHash のハミング距離によるあいまい一致かを選ぶ。
enum DupMatchLevel: Int, CaseIterable {
    case exact = 0, strict, normal, loose

    var label: String {
        switch self {
        case .exact: return "完全一致"
        case .strict: return "厳密"
        case .normal: return "標準"
        case .loose: return "ゆるい"
        }
    }

    /// dHash のハミング距離のしきい値(exact はバイト単位比較のため未使用)。
    var threshold: Int {
        switch self {
        case .exact: return 0
        case .strict: return 2
        case .normal: return 5
        case .loose: return 9
        }
    }
}

/// 各グループでどの1枚を残すか。
enum DupKeepRule: Int, CaseIterable {
    case highestResolution = 0, largestFile, newest, oldest

    var label: String {
        switch self {
        case .highestResolution: return "解像度が最大のものを残す"
        case .largestFile: return "ファイルサイズが最大のものを残す"
        case .newest: return "最新のものを残す"
        case .oldest: return "最古のものを残す"
        }
    }
}

/// 解析済みの1枚(サイズ・寸法・知覚ハッシュ)。マッチレベルの切り替え時にファイルを
/// 読み直さずグループ化だけやり直せるよう、スキャン時に一度だけ計算しておく。
struct AnalyzedPhoto {
    let item: PhotoItem
    let fileSize: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let dhash: UInt64

    var resolution: Int { pixelWidth * pixelHeight }
}

/// 重複候補 1 件(解析済み写真 + ゴミ箱へ入れるかどうかのチェック状態)。
final class DuplicateCandidate {
    let photo: AnalyzedPhoto
    var markedForTrash: Bool

    init(photo: AnalyzedPhoto, markedForTrash: Bool) {
        self.photo = photo
        self.markedForTrash = markedForTrash
    }
}

struct DuplicateGroupData {
    let id = UUID()
    var candidates: [DuplicateCandidate]
    var isExact: Bool

    /// このグループで最大の1枚を残した場合に回収できるバイト数。
    var wastedBytes: Int64 {
        let total = candidates.reduce(Int64(0)) { $0 + $1.photo.fileSize }
        let biggest = candidates.map { $0.photo.fileSize }.max() ?? 0
        return total - biggest
    }
}

/// SHA-256 を URL ごとにキャッシュする(完全一致判定・あいまい一致グループの
/// isExact 判定の両方から使い回す)。
final class ShaCache {
    private var cache: [URL: String] = [:]
    private let lock = NSLock()

    func sha256(of url: URL) -> String? {
        lock.lock()
        if let cached = cache[url] { lock.unlock(); return cached }
        lock.unlock()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        lock.lock(); cache[url] = sha; lock.unlock()
        return sha
    }
}

/// スレッドセーフなキャンセルフラグ(解析フェーズの並列処理から参照する)。
final class CancelFlag {
    private var flag = false
    private let lock = NSLock()
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

private struct UnionFind {
    private var parent: [Int]
    init(_ n: Int) { parent = Array(0..<n) }
    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var cur = x
        while parent[cur] != root {
            let next = parent[cur]
            parent[cur] = root
            cur = next
        }
        return root
    }
    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[ra] = rb }
    }
}

/// 解析(サイズ・寸法・dHash の並列計算)とグループ化(完全一致 or あいまい一致)を行う。
enum DuplicateScanner {
    static func analyze(photos: [PhotoItem],
                        cancelFlag: CancelFlag,
                        progress: @escaping (Int, Int) -> Void,
                        completion: @escaping ([AnalyzedPhoto]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let total = photos.count
            var results = [AnalyzedPhoto?](repeating: nil, count: total)
            let lock = NSLock()
            var done = 0
            // dHash計算はkCGImageSourceCreateThumbnailFromImageAlwaysでフル解像度デコードを
            // 強制するため、1枚あたり(特にRAW/HEIC)数十〜数百MBを消費しうる。
            // DispatchQueue.concurrentPerformは同時実行数を制御しないため、ファイルI/Oで
            // スレッドがブロックするとGCDがワーカースレッドをコア数以上に増やし、
            // フルデコードが大量に同時進行してメモリを枯渇させることがあった
            // (写真1万枚規模で発生を確認)。ThumbnailLoaderのキューと同じ上限(4)で
            // 同時デコード数を頭打ちにする。
            let concurrencyLimit = 4
            let semaphore = DispatchSemaphore(value: concurrencyLimit)
            let group = DispatchGroup()
            results.withUnsafeMutableBufferPointer { buf in
                let bufPtr = buf
                for i in 0..<total {
                    if cancelFlag.isCancelled { break }
                    semaphore.wait()
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { semaphore.signal(); group.leave() }
                        if cancelFlag.isCancelled { return }
                        bufPtr[i] = analyzeOne(photos[i])
                        lock.lock()
                        done += 1
                        let d = done
                        lock.unlock()
                        if d == total || d % 25 == 0 {
                            DispatchQueue.main.async { progress(d, total) }
                        }
                    }
                }
                group.wait()
            }
            let analyzed = cancelFlag.isCancelled ? [] : results.compactMap { $0 }
            DispatchQueue.main.async { completion(analyzed) }
        }
    }

    private static func analyzeOne(_ item: PhotoItem) -> AnalyzedPhoto? {
        guard let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return nil }
        var width = 0, height = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }
        guard let hash = dHash(source: src) else { return nil }
        return AnalyzedPhoto(item: item, fileSize: Int64(size), pixelWidth: width, pixelHeight: height, dhash: hash)
    }

    /// 9x8 グレースケールに縮小し、隣接ピクセルの明暗で 64bit の知覚ハッシュを作る。
    private static func dHash(source: CGImageSource) -> UInt64? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        let w = 9, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                hash <<= 1
                if pixels[row * w + col] < pixels[row * w + col + 1] { hash |= 1 }
            }
        }
        return hash
    }

    // MARK: グループ化

    static func group(_ photos: [AnalyzedPhoto], level: DupMatchLevel, shaCache: ShaCache) -> [DuplicateGroupData] {
        let rawGroups: [[AnalyzedPhoto]] = level == .exact
            ? groupExact(photos, shaCache: shaCache)
            : groupSimilar(photos, threshold: level.threshold)

        return rawGroups.map { members in
            let sorted = members.sorted { $0.item.mtime < $1.item.mtime }
            let isExact = level == .exact || isExactGroup(sorted, shaCache: shaCache)
            return DuplicateGroupData(
                candidates: sorted.map { DuplicateCandidate(photo: $0, markedForTrash: false) },
                isExact: isExact)
        }
    }

    /// バイト単位の完全一致(サイズ → SHA-256 の二段階)。
    private static func groupExact(_ photos: [AnalyzedPhoto], shaCache: ShaCache) -> [[AnalyzedPhoto]] {
        var bySize: [Int64: [AnalyzedPhoto]] = [:]
        for p in photos { bySize[p.fileSize, default: []].append(p) }
        var groups: [[AnalyzedPhoto]] = []
        for (_, candidates) in bySize where candidates.count > 1 {
            var byHash: [String: [AnalyzedPhoto]] = [:]
            for p in candidates {
                guard let sha = shaCache.sha256(of: p.item.url) else { continue }
                byHash[sha, default: []].append(p)
            }
            groups.append(contentsOf: byHash.values.filter { $0.count > 1 })
        }
        return groups
    }

    /// dHash のハミング距離による Union-Find クラスタリング。
    private static func groupSimilar(_ photos: [AnalyzedPhoto], threshold: Int) -> [[AnalyzedPhoto]] {
        let n = photos.count
        var uf = UnionFind(n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                if (photos[i].dhash ^ photos[j].dhash).nonzeroBitCount <= threshold {
                    uf.union(i, j)
                }
            }
        }
        var clusters: [Int: [AnalyzedPhoto]] = [:]
        for i in 0..<n { clusters[uf.find(i), default: []].append(photos[i]) }
        return clusters.values.filter { $0.count > 1 }.map { $0 }
    }

    /// あいまい一致で見つかったグループが実はバイト完全一致でもあるか(表示バッジ用)。
    private static func isExactGroup(_ members: [AnalyzedPhoto], shaCache: ShaCache) -> Bool {
        guard Set(members.map { $0.fileSize }).count == 1 else { return false }
        let shas = Set(members.compactMap { shaCache.sha256(of: $0.item.url) })
        return shas.count == 1
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// 重複候補 1 件のカード。クリックでゴミ箱行き/残す をトグルする(myorganizer と同じ操作感)。
final class DuplicateItemCard: NSView {
    let candidate: DuplicateCandidate
    var onToggle: (() -> Void)?
    /// これから「ゴミ箱行き」にマークしようとしたとき、許可するかを判定する
    /// (グループが無効化されている/1グループあたりの上限に達している場合はfalse)。
    var canMarkForTrash: (() -> Bool)?

    private let fill = FillImageView(gravity: .resizeAspectFill)
    private let badge = NSImageView()
    /// サムネイルを読み込み済み/リクエスト中かどうか(スクロールで visible/invisible を
    /// 何度も跨いでも同じURLを二重リクエストしないためのガード)。
    private var thumbnailRequested = false

    init(candidate: DuplicateCandidate) {
        self.candidate = candidate
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        let nameLabel = NSTextField(labelWithString: candidate.photo.item.url.lastPathComponent)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let infoLabel = NSTextField(labelWithString:
            "\(candidate.photo.pixelWidth)×\(candidate.photo.pixelHeight) · \(formatBytes(candidate.photo.fileSize))")
        infoLabel.font = .systemFont(ofSize: 10)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 150),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            fill.heightAnchor.constraint(equalToConstant: 120),
            badge.topAnchor.constraint(equalTo: fill.topAnchor, constant: 5),
            badge.leadingAnchor.constraint(equalTo: fill.leadingAnchor, constant: 5),
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
            nameLabel.topAnchor.constraint(equalTo: fill.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            infoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            infoLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            infoLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
        ])

        updateAppearance()

        let menu = NSMenu()
        let reveal = NSMenuItem(title: "Finder で表示", action: #selector(revealInFinder), keyEquivalent: "")
        let open = NSMenuItem(title: "開く", action: #selector(openInDefaultApp), keyEquivalent: "")
        reveal.target = self
        open.target = self
        menu.addItem(reveal)
        menu.addItem(open)
        self.menu = menu
    }

    required init?(coder: NSCoder) { fatalError() }

    /// このカードがスクロール可視範囲に入ったときに呼ぶ(重複検出ウインドウ全体で
    /// 数千枚分のサムネイルを一度に読み込んで大量のメモリを使わないよう、
    /// DuplicatesWindowControllerが可視範囲のカードだけに対して呼び出す)。
    func loadThumbnailIfNeeded() {
        guard !thumbnailRequested else { return }
        thumbnailRequested = true
        if let cached = ThumbnailLoader.shared.cached(candidate.photo.item) {
            fill.image = cached
        } else {
            ThumbnailLoader.shared.request(candidate.photo.item) { [weak self] _, img in
                self?.fill.image = img
            }
        }
    }

    /// 可視範囲から外れたときに呼ぶ。読み込み済みサムネイルを解放し、
    /// 再度可視範囲に入ったら`loadThumbnailIfNeeded()`で読み直せるようにする。
    func unloadThumbnail() {
        thumbnailRequested = false
        fill.image = nil
    }

    override func mouseDown(with event: NSEvent) {
        if !candidate.markedForTrash, canMarkForTrash?() == false {
            return
        }
        candidate.markedForTrash.toggle()
        updateAppearance()
        onToggle?()
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.photo.item.url])
    }

    @objc private func openInDefaultApp() {
        NSWorkspace.shared.open(candidate.photo.item.url)
    }

    private func updateAppearance() {
        let marked = candidate.markedForTrash
        layer?.borderWidth = marked ? 3 : 0
        layer?.borderColor = NSColor.systemRed.cgColor
        badge.image = NSImage(systemSymbolName: marked ? "checkmark.circle.fill" : "circle",
                              accessibilityDescription: nil)
        badge.contentTintColor = marked ? .systemRed : .white
    }
}

/// `GroupSectionView`のカード列(横スクロール領域の中身)を手動フレーム計算で並べる
/// コンテナ。以前は`NSStackView`を使っていたが、誤クラスタリング等で1グループに
/// 数百〜数千枚の候補が集まると、`NSStackView`が隣接カード間に管理する暗黙の間隔制約が
/// カード数に応じて増え、グループを破棄・再構築するたび(重複を検出しなおす・チェックを
/// 外す・削除後の再構築など)にAutoLayoutの制約エンジンが詰まって実機でアプリが
/// ハングするバグの主因になっていた(カードは全て固定サイズ・単純な横一列なので、
/// AutoLayoutを使わずフレームを直接計算するだけで表示上の違いはない)。
final class CardsRowView: NSView {
    private let cardWidth: CGFloat = 150
    private let rowHeight: CGFloat = 190
    private let spacing: CGFloat = 10
    private let inset: CGFloat = 4
    private var nextX: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: inset, height: rowHeight))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// カードを既存の右端に追い足す(`DuplicateItemCard`自身は`translatesAutoresizing
    /// MaskIntoConstraints = false`のままでよい — サイズは自身の内部制約で決まり、
    /// 位置〈frame.origin〉はこの親からの制約を一切張らないので、ここで直接設定した
    /// 値がAutoLayoutに上書きされることはない)。
    func addCard(_ card: DuplicateItemCard) {
        card.frame.origin = NSPoint(x: nextX, y: inset)
        addSubview(card)
        nextX += cardWidth + spacing
        frame.size = NSSize(width: nextX - spacing + inset, height: rowHeight)
    }
}

/// 1 つの重複グループ: 有効/無効チェックボックス + 見出し(完全一致/類似バッジつき) + 横スクロールのカード列。
final class GroupSectionView: NSView {
    let cardsStack = CardsRowView()
    private let checkbox: NSButton
    private let hScroll = NSScrollView()
    /// グループを削除対象から除外/含めるを切り替えたときに呼ばれる(myorganizerの
    /// DupPhotosViewModel.setGroupEnabledと同じ役割)。
    var onToggleEnabled: ((Bool) -> Void)?
    /// このグループの見出し(縦位置)がウインドウの可視矩形に入っているかどうか
    /// (DuplicatesWindowControllerのupdateVisibleThumbnailsが呼ぶsetThumbnailsLoadedで更新)。
    /// メンバーが数百〜数千枚に誤クラスタリングされた巨大グループでも、縦方向だけでなく
    /// このグループ自身の横スクロールの可視範囲外のカードは読み込まない/解放するための状態。
    private var verticallyVisible = false

    init(number: Int, isExact: Bool, count: Int, wastedBytes: Int64, enabled: Bool, capWarning: String?) {
        checkbox = NSButton(checkboxWithTitle: "グループ \(number)", target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        checkbox.state = enabled ? .on : .off
        checkbox.font = .boldSystemFont(ofSize: 12)
        checkbox.toolTip = "チェックを外すと、このグループを削除対象から除外します(誤検出グループの保護用)"
        checkbox.target = self
        checkbox.action = #selector(checkboxTapped)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .firstBaseline
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSTextField(labelWithString: isExact ? "完全一致" : "類似")
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = isExact ? NSColor.systemGreen : NSColor.systemOrange
        badge.drawsBackground = true
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false

        let infoLabel = NSTextField(labelWithString: "\(count) 件 · 最大 \(formatBytes(wastedBytes)) 節約可能")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor

        headerStack.addArrangedSubview(checkbox)
        headerStack.addArrangedSubview(badge)
        headerStack.addArrangedSubview(infoLabel)

        if let capWarning {
            let warnLabel = NSTextField(labelWithString: "⚠️ 上限のため一部のみ自動選択")
            warnLabel.font = .systemFont(ofSize: 10, weight: .semibold)
            warnLabel.textColor = .systemOrange
            warnLabel.toolTip = capWarning
            headerStack.addArrangedSubview(warnLabel)
        }
        addSubview(headerStack)

        cardsStack.alphaValue = enabled ? 1 : 0.4

        hScroll.hasHorizontalScroller = true
        hScroll.hasVerticalScroller = false
        hScroll.drawsBackground = false
        hScroll.documentView = cardsStack
        hScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hScroll)

        // 巨大グループ(誤クラスタリング等で数百〜数千枚)でも、横スクロールで実際に
        // 見えている分だけサムネイルを保持するため、横方向のbounds変化も監視する。
        hScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(horizontalVisibleRectDidChange),
            name: NSView.boundsDidChangeNotification, object: hScroll.contentView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 46),
            badge.heightAnchor.constraint(equalToConstant: 16),
            hScroll.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 6),
            hScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            hScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            hScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            hScroll.heightAnchor.constraint(equalToConstant: 190),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func checkboxTapped() {
        onToggleEnabled?(checkbox.state == .on)
    }

    /// このグループの見出し(縦位置)がウインドウの可視矩形に入った/外れたときに呼ぶ
    /// (DuplicatesWindowControllerがスクロール可視範囲に応じて呼ぶ)。外れたら
    /// 全カードのサムネイルを解放し、入ったら横スクロールの可視範囲分だけ読み込む
    /// (グループ自体は数百〜数千枚に誤クラスタリングされることがあるため、ここで
    /// 全カード分を一度に読み込むと横スクロールで見えていない分まで確保してしまう)。
    func setThumbnailsLoaded(_ loaded: Bool) {
        verticallyVisible = loaded
        if loaded {
            updateHorizontalVisibility()
        } else {
            for case let card as DuplicateItemCard in cardsStack.subviews {
                card.unloadThumbnail()
            }
        }
    }

    @objc private func horizontalVisibleRectDidChange() {
        updateHorizontalVisibility()
    }

    private func updateHorizontalVisibility() {
        guard verticallyVisible else { return }
        let buffer: CGFloat = 320   // 概ねカード2枚分。横スクロール時のちらつきを避けるため
        let visible = hScroll.documentVisibleRect.insetBy(dx: -buffer, dy: 0)
        for case let card as DuplicateItemCard in cardsStack.subviews {
            if card.frame.intersects(visible) {
                card.loadThumbnailIfNeeded()
            } else {
                card.unloadThumbnail()
            }
        }
    }
}

/// 重複検出ウインドウ: 解析(サイズ/寸法/dHash) → グループ化 → 一覧表示。
/// マッチレベル・残す基準は解析後にファイルを読み直さず切り替えられる。
final class DuplicatesWindowController: NSWindowController, NSWindowDelegate {
    private let photos: [PhotoItem]
    private let onTrashed: (Set<String>, [String]) -> Void
    var onClose: (() -> Void)?

    private var analyzed: [AnalyzedPhoto] = []
    private var groups: [DuplicateGroupData] = []
    /// `stack.arrangedSubviews`中の各`GroupSectionView`をグループidで引けるようにしたもの
    /// (`setGroupEnabled`が1グループだけを差し替える際、全件を線形探索せずに済むように)。
    private var sectionViews: [UUID: GroupSectionView] = [:]
    /// 削除対象として扱う(=チェックの入った)グループのid。外したグループは自動選択の対象外になり、
    /// 個々の写真も手動選択できない(誤検出グループを丸ごと除外できるようにするため。myorganizerの
    /// DupPhotosViewModel.enabledGroupsと同じ役割)。
    private var enabledGroupIDs: Set<UUID> = []
    private let shaCache = ShaCache()
    private let cancelFlag = CancelFlag()

    private var matchLevel: DupMatchLevel = .exact {
        didSet { if !analyzed.isEmpty { regroup() } }
    }
    private var keepRule: DupKeepRule = .highestResolution {
        didSet { autoSelect(); rebuildGroupViews(); updateStatus() }
    }
    /// 1グループあたり削除対象にできる枚数の上限。「類似」等の緩いマッチレベルで誤って大きく
    /// クラスタリングされたグループを一気に削除しないための安全策(myorganizerのDupPhotosViewModel.
    /// maxDeletePerGroupと同じ既定値・永続化キーの役割)。
    private var maxDeletePerGroup: Int {
        didSet { UserDefaults.standard.set(maxDeletePerGroup, forKey: "duplicates.maxDeletePerGroup") }
    }

    private let statusLabel = NSTextField(labelWithString: "スキャン中…")
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton(title: "キャンセル", target: nil, action: nil)
    private let matchLevelControl = NSSegmentedControl()
    private let keepRulePopup = NSPopUpButton()
    private let maxDeleteStepper = NSStepper()
    private let maxDeleteLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let selectAllGroupsButton = NSButton(title: "全グループ選択", target: nil, action: nil)
    private let deselectAllGroupsButton = NSButton(title: "全グループ解除", target: nil, action: nil)
    private let autoSelectButton = NSButton(title: "自動選択をやり直す", target: nil, action: nil)
    private let trashButton = NSButton(title: "選択した写真をゴミ箱へ", target: nil, action: nil)

    init(photos: [PhotoItem], onTrashed: @escaping (Set<String>, [String]) -> Void) {
        self.photos = photos
        self.onTrashed = onTrashed
        let saved = UserDefaults.standard.integer(forKey: "duplicates.maxDeletePerGroup")
        maxDeletePerGroup = saved > 0 ? saved : 3
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "重複写真を検出"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupUI()
        startAnalyze()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func windowWillClose(_ notification: Notification) {
        cancelFlag.cancel()
        onClose?()
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        matchLevelControl.segmentStyle = .automatic
        matchLevelControl.segmentCount = DupMatchLevel.allCases.count
        for level in DupMatchLevel.allCases {
            matchLevelControl.setLabel(level.label, forSegment: level.rawValue)
            matchLevelControl.setWidth(56, forSegment: level.rawValue)
        }
        matchLevelControl.selectedSegment = matchLevel.rawValue
        matchLevelControl.target = self
        matchLevelControl.action = #selector(matchLevelChanged)
        matchLevelControl.isEnabled = false
        matchLevelControl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(matchLevelControl)

        for rule in DupKeepRule.allCases {
            keepRulePopup.addItem(withTitle: rule.label)
        }
        keepRulePopup.selectItem(at: keepRule.rawValue)
        keepRulePopup.target = self
        keepRulePopup.action = #selector(keepRuleChanged)
        keepRulePopup.isEnabled = false
        keepRulePopup.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(keepRulePopup)

        maxDeleteStepper.minValue = 1
        maxDeleteStepper.maxValue = 20
        maxDeleteStepper.increment = 1
        maxDeleteStepper.integerValue = maxDeletePerGroup
        maxDeleteStepper.target = self
        maxDeleteStepper.action = #selector(maxDeleteChanged)
        maxDeleteStepper.isEnabled = false
        maxDeleteStepper.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(maxDeleteStepper)

        maxDeleteLabel.stringValue = "1グループ最大\(maxDeletePerGroup)枚"
        maxDeleteLabel.font = .systemFont(ofSize: 11)
        maxDeleteLabel.toolTip = "1つの重複グループ内で削除対象にできる枚数の上限。誤って大きくクラスタリングされたグループを一気に削除しないための安全策です。"
        maxDeleteLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(maxDeleteLabel)

        cancelButton.target = self
        cancelButton.action = #selector(cancelAnalyze)
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(cancelButton)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(progressIndicator)
        progressIndicator.startAnimation(nil)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.documentView = stack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
        content.addSubview(scrollView)

        // 数千件の重複候補があっても表示中の分だけサムネイルを読み込むため、
        // スクロール(・ウインドウリサイズによるbounds変化)を監視する。
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(visibleRectDidChange),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        selectAllGroupsButton.target = self
        selectAllGroupsButton.action = #selector(selectAllGroupsTapped)
        selectAllGroupsButton.bezelStyle = .rounded
        selectAllGroupsButton.isHidden = true
        selectAllGroupsButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(selectAllGroupsButton)

        deselectAllGroupsButton.target = self
        deselectAllGroupsButton.action = #selector(deselectAllGroupsTapped)
        deselectAllGroupsButton.bezelStyle = .rounded
        deselectAllGroupsButton.isHidden = true
        deselectAllGroupsButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(deselectAllGroupsButton)

        autoSelectButton.target = self
        autoSelectButton.action = #selector(autoSelectTapped)
        autoSelectButton.bezelStyle = .rounded
        autoSelectButton.isHidden = true
        autoSelectButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(autoSelectButton)

        trashButton.target = self
        trashButton.action = #selector(trashSelected)
        trashButton.bezelStyle = .rounded
        trashButton.bezelColor = .systemRed
        trashButton.isHidden = true
        trashButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(trashButton)

        NSLayoutConstraint.activate([
            matchLevelControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            matchLevelControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            keepRulePopup.centerYAnchor.constraint(equalTo: matchLevelControl.centerYAnchor),
            keepRulePopup.leadingAnchor.constraint(equalTo: matchLevelControl.trailingAnchor, constant: 12),
            maxDeleteLabel.centerYAnchor.constraint(equalTo: matchLevelControl.centerYAnchor),
            maxDeleteLabel.leadingAnchor.constraint(equalTo: keepRulePopup.trailingAnchor, constant: 14),
            maxDeleteStepper.centerYAnchor.constraint(equalTo: matchLevelControl.centerYAnchor),
            maxDeleteStepper.leadingAnchor.constraint(equalTo: maxDeleteLabel.trailingAnchor, constant: 4),
            cancelButton.centerYAnchor.constraint(equalTo: matchLevelControl.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            progressIndicator.centerYAnchor.constraint(equalTo: matchLevelControl.centerYAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: matchLevelControl.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: trashButton.topAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            selectAllGroupsButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            selectAllGroupsButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            deselectAllGroupsButton.leadingAnchor.constraint(equalTo: selectAllGroupsButton.trailingAnchor, constant: 8),
            deselectAllGroupsButton.centerYAnchor.constraint(equalTo: selectAllGroupsButton.centerYAnchor),
            autoSelectButton.leadingAnchor.constraint(equalTo: deselectAllGroupsButton.trailingAnchor, constant: 8),
            autoSelectButton.centerYAnchor.constraint(equalTo: selectAllGroupsButton.centerYAnchor),
            trashButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            trashButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    // MARK: 解析フェーズ

    private func startAnalyze() {
        DuplicateScanner.analyze(photos: photos, cancelFlag: cancelFlag, progress: { [weak self] done, total in
            self?.statusLabel.stringValue = "解析中… \(done) / \(total) 枚"
        }, completion: { [weak self] analyzed in
            self?.analyzeFinished(analyzed)
        })
    }

    @objc private func cancelAnalyze() {
        cancelFlag.cancel()
    }

    private func analyzeFinished(_ analyzed: [AnalyzedPhoto]) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        cancelButton.isHidden = true
        matchLevelControl.isEnabled = true
        keepRulePopup.isEnabled = true
        maxDeleteStepper.isEnabled = true

        if cancelFlag.isCancelled {
            statusLabel.stringValue = "キャンセルしました"
            return
        }
        self.analyzed = analyzed
        regroup()
    }

    // MARK: グループ化 / 自動選択

    private func regroup() {
        statusLabel.stringValue = "グループ化しています…"
        let photos = analyzed
        let level = matchLevel
        let shaCache = self.shaCache
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let groups = DuplicateScanner.group(photos, level: level, shaCache: shaCache)
                .sorted { $0.wastedBytes > $1.wastedBytes }
            DispatchQueue.main.async {
                guard let self else { return }
                self.groups = groups
                self.enabledGroupIDs = Set(groups.map(\.id))
                self.autoSelect()
                self.afterGroupsChanged()
            }
        }
    }

    private func afterGroupsChanged() {
        let dupCount = groups.reduce(0) { $0 + $1.candidates.count - 1 }
        statusLabel.stringValue = groups.isEmpty
            ? "重複は見つかりませんでした(\(analyzed.count) 枚を検査)"
            : "\(groups.count) グループ・重複 \(dupCount) 枚が見つかりました(\(analyzed.count) 枚を検査)"
        scrollView.isHidden = groups.isEmpty
        selectAllGroupsButton.isHidden = groups.isEmpty
        deselectAllGroupsButton.isHidden = groups.isEmpty
        autoSelectButton.isHidden = groups.isEmpty
        trashButton.isHidden = groups.isEmpty
        rebuildGroupViews()
        updateStatus()
    }

    @objc private func matchLevelChanged() {
        guard let level = DupMatchLevel(rawValue: matchLevelControl.selectedSegment) else { return }
        matchLevel = level
    }

    @objc private func keepRuleChanged() {
        guard let rule = DupKeepRule(rawValue: keepRulePopup.indexOfSelectedItem) else { return }
        keepRule = rule
    }

    @objc private func maxDeleteChanged() {
        maxDeletePerGroup = maxDeleteStepper.integerValue
        maxDeleteLabel.stringValue = "1グループ最大\(maxDeletePerGroup)枚"
        autoSelect()
        rebuildGroupViews()
        updateStatus()
    }

    @objc private func autoSelectTapped() {
        autoSelect()
        rebuildGroupViews()
        updateStatus()
    }

    @objc private func selectAllGroupsTapped() {
        enabledGroupIDs = Set(groups.map(\.id))
        autoSelect()
        rebuildGroupViews()
        updateStatus()
    }

    @objc private func deselectAllGroupsTapped() {
        enabledGroupIDs = []
        for group in groups {
            for c in group.candidates { c.markedForTrash = false }
        }
        rebuildGroupViews()
        updateStatus()
    }

    /// グループ単位の「このグループの重複を削除するか」チェックボックス用。他のグループの
    /// 選択状態には触れない(手動選択を保持するため、全体のautoSelect()は呼ばない。myorganizerの
    /// DupPhotosViewModel.setGroupEnabledと同じ役割)。
    private func setGroupEnabled(_ group: DuplicateGroupData, enabled: Bool) {
        if enabled {
            enabledGroupIDs.insert(group.id)
            applyAutoSelect(to: group)
        } else {
            enabledGroupIDs.remove(group.id)
            for c in group.candidates { c.markedForTrash = false }
        }
        // このグループだけを差し替える(rebuildGroupViews()で全グループを作り直すと、
        // 誤クラスタリング等で候補が数千件規模のライブラリではチェック1つのトグルのたびに
        // 全グループ分のAutoLayout制約が破棄・再構築され、実機でアプリがハングする
        // 原因になっていた)。
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            updateSection(for: group, at: index)
        }
        updateStatus()
    }

    /// keepRule に従って、有効なグループだけ「残す1枚」以外を上限(maxDeletePerGroup)まで選択する。
    /// 無効化したグループはここで明示的にクリアする(誤検出グループを丸ごと除外するため)。
    private func autoSelect() {
        for group in groups {
            if enabledGroupIDs.contains(group.id) {
                applyAutoSelect(to: group)
            } else {
                for c in group.candidates { c.markedForTrash = false }
            }
        }
    }

    private func applyAutoSelect(to group: DuplicateGroupData) {
        for c in group.candidates { c.markedForTrash = false }
        guard let keeper = keeper(in: group) else { return }
        let others = group.candidates.filter { $0 !== keeper }
        for c in others.prefix(maxDeletePerGroup) { c.markedForTrash = true }
    }

    private func keeper(in group: DuplicateGroupData) -> DuplicateCandidate? {
        switch keepRule {
        case .highestResolution:
            return group.candidates.max {
                ($0.photo.resolution, $0.photo.fileSize) < ($1.photo.resolution, $1.photo.fileSize)
            }
        case .largestFile:
            return group.candidates.max { $0.photo.fileSize < $1.photo.fileSize }
        case .newest:
            return group.candidates.max { $0.photo.item.mtime < $1.photo.item.mtime }
        case .oldest:
            return group.candidates.min { $0.photo.item.mtime < $1.photo.item.mtime }
        }
    }

    // MARK: 表示

    /// 1グループ分の見出し + 横スクロールのカード列を組み立てる(`rebuildGroupViews`と
    /// `updateSection`の両方から使う共通処理)。
    private func makeSection(index: Int, group: DuplicateGroupData) -> GroupSectionView {
        let enabled = enabledGroupIDs.contains(group.id)
        let overflow = group.candidates.count - 1 - maxDeletePerGroup
        let capWarning: String? = overflow > 0
            ? "このグループは\(group.candidates.count - 1)枚が削除候補ですが、1グループあたりの上限(\(maxDeletePerGroup)枚)のため一部しか自動選択されていません。残りを削除するには手動で選択してください(上限までのみ)。"
            : nil
        let section = GroupSectionView(
            number: index + 1, isExact: group.isExact,
            count: group.candidates.count, wastedBytes: group.wastedBytes,
            enabled: enabled, capWarning: capWarning)
        section.onToggleEnabled = { [weak self] newValue in
            self?.setGroupEnabled(group, enabled: newValue)
        }
        for cand in group.candidates {
            let card = DuplicateItemCard(candidate: cand)
            card.onToggle = { [weak self] in self?.updateStatus() }
            card.canMarkForTrash = { [weak self] in
                guard let self, self.enabledGroupIDs.contains(group.id) else { return false }
                let current = group.candidates.filter { $0.markedForTrash }.count
                if current >= self.maxDeletePerGroup {
                    self.statusLabel.stringValue = "1グループあたり削除対象にできるのは最大\(self.maxDeletePerGroup)枚までです"
                    return false
                }
                return true
            }
            section.cardsStack.addCard(card)
        }
        return section
    }

    private func rebuildGroupViews() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sectionViews.removeAll()
        for (i, group) in groups.enumerated() {
            let section = makeSection(index: i, group: group)
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
            sectionViews[group.id] = section
        }
        // レイアウト確定後(次のランループ)でないとsection.frameがまだ古い/ゼロのままなので、
        // 可視判定を1ティック遅らせる。
        DispatchQueue.main.async { [weak self] in self?.updateVisibleThumbnails() }
    }

    /// `setGroupEnabled`専用: 1グループの見出し/カード列だけを作り直して同じ位置に差し替える
    /// (他のグループのビューには一切触れないので、候補数千件規模のライブラリでもO(そのグループの
    /// 件数)で済む)。
    private func updateSection(for group: DuplicateGroupData, at index: Int) {
        guard let old = sectionViews[group.id] else { rebuildGroupViews(); return }
        old.removeFromSuperview()
        let new = makeSection(index: index, group: group)
        stack.insertArrangedSubview(new, at: min(index, stack.arrangedSubviews.count))
        new.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        sectionViews[group.id] = new
        DispatchQueue.main.async { [weak self] in self?.updateVisibleThumbnails() }
    }

    @objc private func visibleRectDidChange() {
        updateVisibleThumbnails()
    }

    /// スクロールの可視矩形(前後にバッファを付けたもの)と交差するグループだけ
    /// サムネイルを読み込み、外れたグループは解放する。重複候補が数千件あっても
    /// 画面に出ている分だけがメモリ上のサムネイルを保持するようにするための仕組み
    /// (メイン写真グリッドのNSCollectionViewによるセル再利用と同じ狙いを、
    /// この画面ではプレーンなNSStackViewの上に手動で実現している)。
    private func updateVisibleThumbnails() {
        let buffer: CGFloat = 460   // 概ねグループ2つ分。スクロール時のちらつきを避けるため
        let visible = scrollView.documentVisibleRect.insetBy(dx: 0, dy: -buffer)
        for case let section as GroupSectionView in stack.arrangedSubviews {
            section.setThumbnailsLoaded(section.frame.intersects(visible))
        }
    }

    private func updateStatus() {
        let all = groups.flatMap { $0.candidates }
        let marked = all.filter { $0.markedForTrash }
        let totalBytes = marked.reduce(Int64(0)) { $0 + $1.photo.fileSize }
        trashButton.title = "選択した \(marked.count) 枚をゴミ箱へ(\(formatBytes(totalBytes)))"
        trashButton.isEnabled = !marked.isEmpty
    }

    // MARK: 削除(ゴミ箱へ移動)

    @objc private func trashSelected() {
        let toTrash = groups.flatMap { $0.candidates }.filter { $0.markedForTrash }
        guard !toTrash.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "\(toTrash.count) 枚をゴミ箱に入れますか?"
        alert.informativeText = "Finder のゴミ箱からいつでも戻せます。"
        alert.addButton(withTitle: "ゴミ箱に入れる")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var removed = Set<String>()
        var failures: [String] = []
        for c in toTrash {
            do {
                try FileManager.default.trashItem(at: c.photo.item.url, resultingItemURL: nil)
                removed.insert(c.photo.item.url.path)
            } catch {
                failures.append(c.photo.item.url.lastPathComponent)
            }
        }

        onTrashed(removed, failures)

        analyzed.removeAll { removed.contains($0.item.url.path) }
        groups = groups
            .map { g -> DuplicateGroupData in
                var g = g
                g.candidates.removeAll { removed.contains($0.photo.item.url.path) }
                return g
            }
            .filter { $0.candidates.count > 1 }
        enabledGroupIDs = enabledGroupIDs.intersection(groups.map(\.id))
        afterGroupsChanged()
    }
}

// MARK: - Photo filtering (date range + person detection)

enum DateRangeFilter: Equatable {
    case all
    case today
    case thisWeek
    case thisMonth
    case custom(from: Date, to: Date)

    func apply(to items: [PhotoItem]) -> [PhotoItem] {
        guard let interval = interval() else { return items }
        return items.filter { interval.contains($0.mtime) }
    }

    private func interval() -> DateInterval? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all:
            return nil
        case .today:
            return cal.dateInterval(of: .day, for: now)
        case .thisWeek:
            return cal.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth:
            return cal.dateInterval(of: .month, for: now)
        case .custom(let from, let to):
            let start = cal.startOfDay(for: min(from, to))
            let endDay = cal.startOfDay(for: max(from, to))
            let end = cal.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: end)
        }
    }
}

enum PersonFilter: Int {
    case all = 0, hasPerson, noPerson
}

enum IllustrationFilter: Int {
    case all = 0, illustrationOnly, photoOnly
}

struct PhotoFilter {
    var dateRange: DateRangeFilter = .all
    var personFilter: PersonFilter = .all
    var illustrationFilter: IllustrationFilter = .all
    var rioFilter: RioFilter = .all
    /// 手動仕分け(`SortMode.swift`)による絞り込み。
    var manualFilter: ManualFilter = .all
    /// 璃央判定の距離閾値(大きいほどゆるい)。`RioMatcher.swift`参照。
    var rioThreshold: Float = 0.5
    var isActive: Bool { dateRange != .all || personFilter != .all || illustrationFilter != .all || rioFilter != .all || manualFilter != .all }
}

/// Vision の顔検出結果を (パス, mtime) キーでキャッシュする。ファイルが変われば
/// mtime が変わるので古い判定結果は使われない。判定はセッション内メモリのみ
/// (ディスク永続化はしない)。
final class FaceCache {
    private var results: [String: Bool] = [:]
    private let lock = NSLock()
    private var cancelFlag = CancelFlag()

    func result(for item: PhotoItem) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return results[key(for: item)]
    }

    /// まだ未解析の写真だけを顔検出し、キャッシュに書き込む。
    /// Visionは内部でNeural Engine/GPU処理を直列化しているため、concurrentPerformで
    /// 一度に大量投入すると「Vision待ちでブロックされたGCDスレッド」が積み上がり、
    /// ディスパッチのワーカースレッド上限(既定64)に達してアプリ全体がハングする
    /// (フィルター切替中にQuitすると顔検出の残タスクが捌け切るまで終了できない、
    /// という実機ハングの原因だった)。OperationQueueで同時実行数を絞り、
    /// フィルターを切り替えたら古い解析はcancelFlagで打ち切る。
    func analyze(_ items: [PhotoItem],
                progress: @escaping (Int, Int) -> Void,
                completion: @escaping () -> Void) {
        let total = items.count
        guard total > 0 else { completion(); return }
        cancelFlag.cancel()
        let flag = CancelFlag()
        cancelFlag = flag

        DispatchQueue.global(qos: .userInitiated).async {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
            queue.qualityOfService = .userInitiated

            let lock = NSLock()
            var done = 0
            for item in items {
                queue.addOperation {
                    if flag.isCancelled { return }
                    let has = Self.detectFace(url: item.url)
                    self.store(has, for: item)
                    lock.lock()
                    done += 1
                    let d = done
                    lock.unlock()
                    if !flag.isCancelled, d == total || d % 10 == 0 {
                        DispatchQueue.main.async { progress(d, total) }
                    }
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            if !flag.isCancelled {
                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// フィルター変更やアプリ終了時に、実行中/待機中の顔検出を打ち切る。
    func cancelCurrent() {
        cancelFlag.cancel()
    }

    private func store(_ has: Bool, for item: PhotoItem) {
        lock.lock(); results[key(for: item)] = has; lock.unlock()
    }

    private func key(for item: PhotoItem) -> String {
        "\(item.url.path)|\(item.mtime.timeIntervalSince1970)"
    }

    /// 速度優先でダウンサンプルした画像に対して Vision の人物検出をかける
    /// (EXIF の向きを反映してから縮小するので、回転していても正しく検出できる)。
    /// 顔検出(VNDetectFaceRectanglesRequest)だけだと後ろ向き・横向きなど顔が写っていない
    /// 人物を見逃して「人物なし」に誤分類してしまうため、人体検出
    /// (VNDetectHumanRectanglesRequest。顔が見えなくても上半身/全身のシルエットで検出できる)
    /// も併用し、どちらかで検出できれば「人物あり」とする。
    private static func detectFace(url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return false }
        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([faceRequest, humanRequest])
        let hasFace = !(faceRequest.results?.isEmpty ?? true)
        let hasHuman = !(humanRequest.results?.isEmpty ?? true)
        return hasFace || hasHuman
    }
}

/// イラスト判定結果を (パス, mtime) キーでキャッシュする(`FaceCache`と同じパターン。
/// セッション内メモリのみ、ディスク永続化はしない)。判定は2段階:
/// ① EXIFにカメラのMake/Model/レンズ情報が一切無ければ「非写真」候補とする(実際のカメラ
/// 写真はここでほぼ弾かれるので、大半のファイルは高価なVision分類を通らずに済む)。
/// ② 候補だけ Vision の汎用画像分類(`VNClassifyImageRequest`)にかけ、上位の分類ラベルに
/// イラスト/漫画/絵らしいものが含まれていれば「イラスト」と判定する。Visionにはこの
/// 用途専用の分類器は無い(README参照)ため、①のEXIFヒューリスティックと組み合わせることで
/// 実写真の誤検出(②単体のブレ)を抑えている。
final class IllustrationCache {
    private var results: [String: Bool] = [:]
    private let lock = NSLock()
    private var cancelFlag = CancelFlag()

    func result(for item: PhotoItem) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return results[key(for: item)]
    }

    /// まだ未判定の写真だけを判定し、キャッシュに書き込む(`FaceCache.analyze`と同じ
    /// OperationQueueベースの並列化・キャンセル方式。理由もFaceCacheと同様: Visionの
    /// 内部直列化とGCDワーカースレッド枯渇を避けるため)。
    func analyze(_ items: [PhotoItem],
                progress: @escaping (Int, Int) -> Void,
                completion: @escaping () -> Void) {
        let total = items.count
        guard total > 0 else { completion(); return }
        cancelFlag.cancel()
        let flag = CancelFlag()
        cancelFlag = flag

        DispatchQueue.global(qos: .userInitiated).async {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
            queue.qualityOfService = .userInitiated

            let lock = NSLock()
            var done = 0
            for item in items {
                queue.addOperation {
                    if flag.isCancelled { return }
                    let isIllust = Self.classify(url: item.url)
                    self.store(isIllust, for: item)
                    lock.lock()
                    done += 1
                    let d = done
                    lock.unlock()
                    if !flag.isCancelled, d == total || d % 10 == 0 {
                        DispatchQueue.main.async { progress(d, total) }
                    }
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            if !flag.isCancelled {
                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// フィルター変更やアプリ終了時に、実行中/待機中の判定を打ち切る。
    func cancelCurrent() {
        cancelFlag.cancel()
    }

    private func store(_ isIllust: Bool, for item: PhotoItem) {
        lock.lock(); results[key(for: item)] = isIllust; lock.unlock()
    }

    private func key(for item: PhotoItem) -> String {
        "\(item.url.path)|\(item.mtime.timeIntervalSince1970)"
    }

    private static func classify(url: URL) -> Bool {
        guard !hasCameraMetadata(url: url) else { return false }
        return classifiedAsIllustration(url: url)
    }

    /// TIFF(Make/Model)・EXIF(LensModel)のいずれかにカメラ由来の値が入っていれば
    /// 実カメラで撮影された写真とみなす。スクリーンショットやダウンロード画像・
    /// 生成画像はこれらが空になることが多く、イラスト判定の一次フィルターとして使える。
    private static func hasCameraMetadata(url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return false }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        let lens = exif?[kCGImagePropertyExifLensModel] as? String
        return !(make ?? "").isEmpty || !(model ?? "").isEmpty || !(lens ?? "").isEmpty
    }

    private static let illustrationKeywords = [
        "illustration", "cartoon", "anime", "comic", "drawing", "sketch",
        "clip art", "clipart", "painting", "digital art", "artwork", "graphic",
        "line art", "animated", "vector",
    ]

    /// 縮小画像を Vision の汎用画像分類にかけ、上位の分類ラベルにイラスト系キーワードが
    /// 含まれるか調べる(専用分類器ではないため確信度がある程度高いものだけを見る)。
    private static func classifiedAsIllustration(url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return false }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        guard let results = request.results else { return false }
        for obs in results.prefix(15) where obs.confidence > 0.3 {
            let id = obs.identifier.lowercased()
            if illustrationKeywords.contains(where: { id.contains($0) }) {
                return true
            }
        }
        return false
    }
}

/// 画質(ブレ・ピンボケ)のスコアを (パス, mtime) キーでキャッシュする
/// (`FaceCache`/`IllustrationCache`と同じキャッシュ方式)。スコアは「Laplacian分散」
/// という無参照ブレ指標: グレースケール化した画像に離散ラプラシアン(隣接4画素との差)を
/// かけ、その応答の分散を取る。ピントが合ったくっきりした輪郭が多いほど分散が大きくなり、
/// ブレた画像は輪郭がなだらかになって分散が小さくなる。絶対的な閾値は無く、同じライブラリ内
/// での相対比較(並び替え)専用 — ツールバー/メニューの「画質が良い順」「画質が悪い順」から
/// 使う。ブレ検出には縮小前の埋め込みサムネイルではなくフルデコードが必要
/// (`kCGImageSourceCreateThumbnailFromImageAlways`)なため、`DuplicateScanner`のdHash計算と
/// 同じ理由(RAW/HEICで1枚あたり数十〜数百MB)で同時実行数をセマフォで4に制限する。
final class QualityCache {
    private var results: [String: Double] = [:]
    private let lock = NSLock()
    private var cancelFlag = CancelFlag()

    func result(for item: PhotoItem) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return results[key(for: item)]
    }

    func analyze(_ items: [PhotoItem],
                progress: @escaping (Int, Int) -> Void,
                completion: @escaping () -> Void) {
        let total = items.count
        guard total > 0 else { completion(); return }
        cancelFlag.cancel()
        let flag = CancelFlag()
        cancelFlag = flag

        DispatchQueue.global(qos: .userInitiated).async {
            let semaphore = DispatchSemaphore(value: 4)
            let group = DispatchGroup()
            let lock = NSLock()
            var done = 0
            for item in items {
                if flag.isCancelled { break }
                semaphore.wait()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { semaphore.signal(); group.leave() }
                    if flag.isCancelled { return }
                    let score = Self.sharpnessScore(url: item.url) ?? 0
                    self.store(score, for: item)
                    lock.lock()
                    done += 1
                    let d = done
                    lock.unlock()
                    if !flag.isCancelled, d == total || d % 10 == 0 {
                        DispatchQueue.main.async { progress(d, total) }
                    }
                }
            }
            group.wait()
            if !flag.isCancelled {
                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// フィルター/並び替え変更やアプリ終了時に、実行中/待機中の解析を打ち切る。
    func cancelCurrent() {
        cancelFlag.cancel()
    }

    private func store(_ score: Double, for item: PhotoItem) {
        lock.lock(); results[key(for: item)] = score; lock.unlock()
    }

    private func key(for item: PhotoItem) -> String {
        "\(item.url.path)|\(item.mtime.timeIntervalSince1970)"
    }

    /// 長辺500pxへフルデコード縮小 → グレースケール化 → 離散ラプラシアンの分散。
    private static func sharpnessScore(url: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 500,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let w = thumb.width, h = thumb.height
        guard w >= 3, h >= 3 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: w, height: h))

        var sum = 0.0, sumSq = 0.0
        var count = 0
        pixels.withUnsafeBufferPointer { buf in
            for y in 1..<(h - 1) {
                let row = y * w, rowUp = row - w, rowDown = row + w
                for x in 1..<(w - 1) {
                    let center = Int(buf[row + x])
                    let lap = Int(buf[rowUp + x]) + Int(buf[rowDown + x])
                             + Int(buf[row + x - 1]) + Int(buf[row + x + 1]) - 4 * center
                    let v = Double(lap)
                    sum += v
                    sumSq += v * v
                    count += 1
                }
            }
        }
        guard count > 0 else { return nil }
        let mean = sum / Double(count)
        return max(0, sumSq / Double(count) - mean * mean)
    }
}

/// ツールバーの「並び替え」ボタンから開くポップオーバーの中身。`sortMenuEntries` を
/// ラジオボタン(`NSStackView`の直接の子として並べることで、AppKit標準の
/// 「同じ親を持つradioボタンは自動的に排他選択になる」挙動をそのまま使い、
/// 自前でのグループ管理をしていない)の縦並びとして表示する。
final class SortPopoverViewController: NSViewController {
    var onSelect: ((SortOrder) -> Void)?
    private var buttons: [NSButton] = []

    func setSelected(_ order: SortOrder) {
        for b in buttons { b.state = (SortOrder(rawValue: b.tag) == order) ? .on : .off }
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 10))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (title, order) in sortMenuEntries {
            let b = NSButton(radioButtonWithTitle: title, target: self, action: #selector(radioClicked(_:)))
            b.tag = order.rawValue
            stack.addArrangedSubview(b)
            buttons.append(b)
        }

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        root.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        view = root
    }

    @objc private func radioClicked(_ sender: NSButton) {
        guard let order = SortOrder(rawValue: sender.tag) else { return }
        onSelect?(order)
    }
}

/// ツールバーの「フィルター」ボタンから開くポップオーバーの中身。
/// 日付範囲(すべて/今日/今週/今月/カスタム)と人物あり/なしを切り替えられる。
final class FilterPopoverViewController: NSViewController {
    var onChange: ((PhotoFilter) -> Void)?
    private(set) var filter = PhotoFilter()

    private let dateControl = NSSegmentedControl()
    private let fromPicker = NSDatePicker()
    private let toPicker = NSDatePicker()
    private let customStack = NSStackView()
    private let personControl = NSSegmentedControl()
    private let illustrationControl = NSSegmentedControl()
    private let rioLabel = NSTextField(labelWithString: "璃央")
    private let rioControl = NSSegmentedControl()
    private let rioSlider = NSSlider(value: 0.5, minValue: 0.2, maxValue: 1.0, target: nil, action: nil)
    private let rioHint = NSTextField(labelWithString: "判定のゆるさ: 左=厳しい / 右=ゆるい")
    private let manualLabel = NSTextField(labelWithString: "仕分け(手動)")
    private let manualControl = NSSegmentedControl()
    private let statusLabel = NSTextField(labelWithString: "")

    override func viewWillAppear() {
        super.viewWillAppear()
        rioLabel.stringValue = "璃央(登録 \(RioReferenceStore.shared.count) 枚)"
        let c = ManualLabelStore.shared.counts
        manualLabel.stringValue = "仕分け(手動) 璃央 \(c.rio) / 璃央以外 \(c.other)"
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 280))

        let dateLabel = NSTextField(labelWithString: "日付")
        dateLabel.font = .boldSystemFont(ofSize: 11)

        dateControl.segmentStyle = .automatic
        dateControl.segmentCount = 5
        for (i, l) in ["すべて", "今日", "今週", "今月", "カスタム"].enumerated() {
            dateControl.setLabel(l, forSegment: i)
            dateControl.setWidth(56, forSegment: i)
        }
        dateControl.selectedSegment = 0
        dateControl.target = self
        dateControl.action = #selector(dateControlChanged)

        let now = Date()
        fromPicker.datePickerStyle = .textFieldAndStepper
        fromPicker.datePickerElements = .yearMonthDay
        fromPicker.dateValue = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        fromPicker.target = self
        fromPicker.action = #selector(customDateChanged)

        toPicker.datePickerStyle = .textFieldAndStepper
        toPicker.datePickerElements = .yearMonthDay
        toPicker.dateValue = now
        toPicker.target = self
        toPicker.action = #selector(customDateChanged)

        let fromLabel = NSTextField(labelWithString: "〜")

        customStack.orientation = .horizontal
        customStack.spacing = 4
        customStack.addArrangedSubview(fromPicker)
        customStack.addArrangedSubview(fromLabel)
        customStack.addArrangedSubview(toPicker)
        customStack.isHidden = true

        let personLabel = NSTextField(labelWithString: "人物")
        personLabel.font = .boldSystemFont(ofSize: 11)

        personControl.segmentStyle = .automatic
        personControl.segmentCount = 3
        for (i, l) in ["すべて", "人物あり", "人物なし"].enumerated() {
            personControl.setLabel(l, forSegment: i)
            personControl.setWidth(72, forSegment: i)
        }
        personControl.selectedSegment = 0
        personControl.target = self
        personControl.action = #selector(personControlChanged)

        let illustLabel = NSTextField(labelWithString: "種類")
        illustLabel.font = .boldSystemFont(ofSize: 11)

        illustrationControl.segmentStyle = .automatic
        illustrationControl.segmentCount = 3
        for (i, l) in ["すべて", "イラストのみ", "写真のみ"].enumerated() {
            illustrationControl.setLabel(l, forSegment: i)
            illustrationControl.setWidth(72, forSegment: i)
        }
        illustrationControl.selectedSegment = 0
        illustrationControl.target = self
        illustrationControl.action = #selector(illustrationControlChanged)

        rioLabel.font = .boldSystemFont(ofSize: 11)
        rioControl.segmentStyle = .automatic
        rioControl.segmentCount = 3
        for (i, l) in ["すべて", "璃央", "璃央以外"].enumerated() {
            rioControl.setLabel(l, forSegment: i)
            rioControl.setWidth(72, forSegment: i)
        }
        rioControl.selectedSegment = 0
        rioControl.target = self
        rioControl.action = #selector(rioControlChanged)
        rioSlider.isContinuous = false
        rioSlider.floatValue = filter.rioThreshold
        rioSlider.target = self
        rioSlider.action = #selector(rioSliderChanged)
        rioHint.font = .systemFont(ofSize: 10)
        rioHint.textColor = .secondaryLabelColor

        manualLabel.font = .boldSystemFont(ofSize: 11)
        manualControl.segmentStyle = .automatic
        manualControl.segmentCount = 4
        for (i, l) in ["すべて", "璃央", "璃央以外", "未仕分け"].enumerated() {
            manualControl.setLabel(l, forSegment: i)
            manualControl.setWidth(54, forSegment: i)
        }
        manualControl.selectedSegment = 0
        manualControl.target = self
        manualControl.action = #selector(manualControlChanged)

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let resetButton = NSButton(title: "フィルターを解除", target: self, action: #selector(resetTapped))
        resetButton.bezelStyle = .rounded

        for v in [dateLabel, dateControl, customStack, personLabel, personControl,
                  illustLabel, illustrationControl, rioLabel, rioControl, rioSlider, rioHint, manualLabel, manualControl, statusLabel, resetButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }

        NSLayoutConstraint.activate([
            dateLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            dateLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            dateControl.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 6),
            dateControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            customStack.topAnchor.constraint(equalTo: dateControl.bottomAnchor, constant: 8),
            customStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            personLabel.topAnchor.constraint(equalTo: customStack.bottomAnchor, constant: 12),
            personLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            personControl.topAnchor.constraint(equalTo: personLabel.bottomAnchor, constant: 6),
            personControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            illustLabel.topAnchor.constraint(equalTo: personControl.bottomAnchor, constant: 12),
            illustLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            illustrationControl.topAnchor.constraint(equalTo: illustLabel.bottomAnchor, constant: 6),
            illustrationControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            rioLabel.topAnchor.constraint(equalTo: illustrationControl.bottomAnchor, constant: 12),
            rioLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            rioControl.topAnchor.constraint(equalTo: rioLabel.bottomAnchor, constant: 6),
            rioControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            rioSlider.topAnchor.constraint(equalTo: rioControl.bottomAnchor, constant: 8),
            rioSlider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            rioSlider.widthAnchor.constraint(equalToConstant: 216),
            rioHint.topAnchor.constraint(equalTo: rioSlider.bottomAnchor, constant: 2),
            rioHint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            manualLabel.topAnchor.constraint(equalTo: rioHint.bottomAnchor, constant: 12),
            manualLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            manualControl.topAnchor.constraint(equalTo: manualLabel.bottomAnchor, constant: 6),
            manualControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            statusLabel.topAnchor.constraint(equalTo: manualControl.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            resetButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            resetButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            resetButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])

        // 項目が増えて(璃央フィルター追加)初期フレームの高さ(280)を超えたため、下の方
        // (璃央のスライダー・状態表示・「フィルターを解除」)がポップオーバーからはみ出して
        // 操作できなくなっていた。実際に必要な高さへ合わせる。
        root.layoutSubtreeIfNeeded()
        root.setFrameSize(NSSize(width: 320, height: max(280, root.fittingSize.height)))
        preferredContentSize = root.frame.size

        view = root
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    @objc private func dateControlChanged() {
        switch dateControl.selectedSegment {
        case 0: filter.dateRange = .all
        case 1: filter.dateRange = .today
        case 2: filter.dateRange = .thisWeek
        case 3: filter.dateRange = .thisMonth
        default: filter.dateRange = .custom(from: fromPicker.dateValue, to: toPicker.dateValue)
        }
        customStack.isHidden = dateControl.selectedSegment != 4
        onChange?(filter)
    }

    @objc private func customDateChanged() {
        guard dateControl.selectedSegment == 4 else { return }
        filter.dateRange = .custom(from: fromPicker.dateValue, to: toPicker.dateValue)
        onChange?(filter)
    }

    @objc private func personControlChanged() {
        filter.personFilter = PersonFilter(rawValue: personControl.selectedSegment) ?? .all
        onChange?(filter)
    }

    @objc private func illustrationControlChanged() {
        filter.illustrationFilter = IllustrationFilter(rawValue: illustrationControl.selectedSegment) ?? .all
        onChange?(filter)
    }

    @objc private func rioControlChanged() {
        filter.rioFilter = RioFilter(rawValue: rioControl.selectedSegment) ?? .all
        onChange?(filter)
    }

    @objc private func manualControlChanged() {
        filter.manualFilter = ManualFilter(rawValue: manualControl.selectedSegment) ?? .all
        onChange?(filter)
    }

    @objc private func rioSliderChanged() {
        filter.rioThreshold = rioSlider.floatValue
        if filter.rioFilter != .all { onChange?(filter) }
    }

    @objc private func resetTapped() {
        filter = PhotoFilter()
        rioControl.selectedSegment = 0
        manualControl.selectedSegment = 0
        rioSlider.floatValue = filter.rioThreshold
        dateControl.selectedSegment = 0
        personControl.selectedSegment = 0
        illustrationControl.selectedSegment = 0
        customStack.isHidden = true
        statusLabel.stringValue = ""
        onChange?(filter)
    }
}

/// ツールバーの「スライドショー」ボタンから開くポップオーバーの中身。
/// ランダム再生・写真の表示秒数・時間制限・自動全画面のオン/オフを設定し、
/// 「スライドショー開始」ボタンで実際に開始する(MySlideshowの`HomeView`の
/// 「スライドショー設定」`GroupBox`と同じ項目、表示モードはこのアプリでは
/// 全画面のみなのでピッカーは無い)。
final class SlideshowSettingsPopoverViewController: NSViewController {
    var onStart: (() -> Void)?

    private let shuffleCheckbox = NSButton(checkboxWithTitle: "ランダム再生", target: nil, action: nil)
    private let durationSlider = NSSlider(value: 6, minValue: 3, maxValue: 15, target: nil, action: nil)
    private let durationLabel = NSTextField(labelWithString: "")
    private let timeLimitSlider = NSSlider(value: 0, minValue: 0, maxValue: 12, target: nil, action: nil)
    private let timeLimitLabel = NSTextField(labelWithString: "")
    private let autoFullscreenCheckbox = NSButton(checkboxWithTitle: "自動的に全画面にする", target: nil, action: nil)

    /// 5分刻み、末尾(index 12)が無制限。MySlideshowの`Settings.timeLimitMinutes`と
    /// 同じ「スライダーの右端が無制限」という設計を踏襲。
    private static let timeLimitOptions: [Int?] = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, nil]

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 10))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        shuffleCheckbox.target = self
        shuffleCheckbox.action = #selector(settingChanged)
        stack.addArrangedSubview(shuffleCheckbox)

        let durationTitle = NSTextField(labelWithString: "表示秒数")
        durationTitle.font = .systemFont(ofSize: 11)
        let durationRow = NSStackView(views: [durationTitle, durationSlider, durationLabel])
        durationRow.orientation = .horizontal
        durationSlider.target = self
        durationSlider.action = #selector(settingChanged)
        durationSlider.isContinuous = true
        durationSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        durationLabel.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(durationRow)

        let timeLimitTitle = NSTextField(labelWithString: "時間制限")
        timeLimitTitle.font = .systemFont(ofSize: 11)
        let timeLimitRow = NSStackView(views: [timeLimitTitle, timeLimitSlider, timeLimitLabel])
        timeLimitRow.orientation = .horizontal
        timeLimitSlider.target = self
        timeLimitSlider.action = #selector(settingChanged)
        timeLimitSlider.numberOfTickMarks = Self.timeLimitOptions.count
        timeLimitSlider.allowsTickMarkValuesOnly = true
        timeLimitSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        timeLimitLabel.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(timeLimitRow)

        autoFullscreenCheckbox.target = self
        autoFullscreenCheckbox.action = #selector(settingChanged)
        stack.addArrangedSubview(autoFullscreenCheckbox)

        let startButton = NSButton(title: "スライドショー開始", target: self, action: #selector(startTapped))
        startButton.bezelStyle = .rounded
        stack.addArrangedSubview(startButton)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        root.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loadFromSettings()
    }

    private func loadFromSettings() {
        shuffleCheckbox.state = GallerySettings.slideshowShuffleEnabled ? .on : .off
        durationSlider.doubleValue = GallerySettings.slideshowPhotoDurationSeconds
        durationLabel.stringValue = "\(Int(durationSlider.doubleValue))秒"
        timeLimitSlider.maxValue = Double(Self.timeLimitOptions.count - 1)
        let idx = Self.timeLimitOptions.firstIndex { $0 == GallerySettings.slideshowTimeLimitMinutes }
            ?? (Self.timeLimitOptions.count - 1)
        timeLimitSlider.doubleValue = Double(idx)
        timeLimitLabel.stringValue = Self.timeLimitOptions[idx].map { "\($0)分" } ?? "無制限"
        autoFullscreenCheckbox.state = GallerySettings.slideshowAutoFullscreen ? .on : .off
    }

    @objc private func settingChanged() {
        GallerySettings.slideshowShuffleEnabled = shuffleCheckbox.state == .on
        let duration = durationSlider.doubleValue.rounded()
        GallerySettings.slideshowPhotoDurationSeconds = duration
        durationLabel.stringValue = "\(Int(duration))秒"
        let idx = Int(timeLimitSlider.doubleValue.rounded())
        let minutes = Self.timeLimitOptions[min(max(idx, 0), Self.timeLimitOptions.count - 1)]
        GallerySettings.slideshowTimeLimitMinutes = minutes
        timeLimitLabel.stringValue = minutes.map { "\($0)分" } ?? "無制限"
        GallerySettings.slideshowAutoFullscreen = autoFullscreenCheckbox.state == .on
    }

    @objc private func startTapped() {
        onStart?()
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
    private var duplicatesWC: DuplicatesWindowController?
    /// `duplicatesWC`が検査対象にしている写真のパス集合(チェックが変わったかの判定用)。
    private var duplicatesScopePaths: Set<String> = []

    private let slideshow = SlideshowController()
    private var slideshowSettingsPopover: NSPopover?
    private var slideshowSettingsVC: SlideshowSettingsPopoverViewController?

    private var sortOrder: SortOrder = .dateDesc {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: defaultsSortKey)
            updateThumbnailBadge()
            // 年月グリッド区切り線(2026-09-07)は日付順のときだけ意味を持つ。
            gridVC.groupingEnabled = sortOrder.isDateOrder
        }
    }

    /// サムネイル左上に月日バッジを表示するかどうか(2026-09-07追加、ユーザー要望
    /// 「サムネに月日を表示できる?」「月日の表示はトグルにしたい」への対応)。
    /// 右下のサイズ/画質バッジ(`gridVC.thumbnailBadge`、下記)とは別スロットなので、
    /// 両方同時にオンにできる。
    private var showDateBadge = false {
        didSet {
            UserDefaults.standard.set(showDateBadge, forKey: defaultsDateBadgeKey)
            gridVC.showDateBadge = showDateBadge
            dateBadgeButton?.state = showDateBadge ? .on : .off
        }
    }

    /// サムネイル右下にファイルサイズバッジを表示するかどうか(2026-09-07追加、
    /// ユーザー要望「ファイルサイズの表示トグルボタンもお願い」への対応)。
    /// サイズ順で並び替えているときは、このトグルの状態に関わらず**強制的に**
    /// 表示する(同ユーザー要望「サイズソートのときは、強制表示で」)―
    /// `updateThumbnailBadge()`の`sortOrder.showsFileSize ||`がその強制分岐。
    private var showSizeBadge = false {
        didSet {
            UserDefaults.standard.set(showSizeBadge, forKey: defaultsSizeBadgeKey)
            updateThumbnailBadge()
            sizeBadgeButton?.state = showSizeBadge ? .on : .off
        }
    }

    /// 右下バッジ(サイズ/画質、排他 ― 1スロットなので優先順位で決める)。
    /// 画質順ソート中は画質を最優先(画質順に切り替えた本来の目的なので、サイズ
    /// トグルがオンでも画質を隠さない)。それ以外はサイズトグルがオン、または
    /// サイズ順ソート中(強制表示)ならサイズを出す。
    private func updateThumbnailBadge() {
        if sortOrder.showsQuality {
            gridVC.thumbnailBadge = .quality
        } else if showSizeBadge || sortOrder.showsFileSize {
            gridVC.thumbnailBadge = .fileSize
        } else {
            gridVC.thumbnailBadge = .none
        }
    }

    /// 通常視聴ビューアで、動画が最後まで再生し終わったら自動的に次のアイテムへ
    /// 進めるかどうか(2026-09-07追加、ユーザー要望「次の動画に自動再生、トグル
    /// ボタンを作って」への対応)。スライドショーとは独立の機能(スライドショーは
    /// 別途タイマー・一時停止状態を持つ専用モード) ― こちらは普段のブラウジング中に
    /// 動画を連続再生したいだけの、もっと軽い機能という位置づけ。ローカル・OneDrive
    /// どちらでも動く(`ViewerOverlay`自体がソースを意識しない作りなので制限する
    /// 理由が無い)。
    private var autoplayNextVideo = false {
        didSet {
            UserDefaults.standard.set(autoplayNextVideo, forKey: defaultsAutoplayNextKey)
            viewer?.autoplayNext = autoplayNextVideo
            autoplayNextButton?.state = autoplayNextVideo ? .on : .off
        }
    }

    private var currentFilter = PhotoFilter()
    private var currentBaseCount = 0
    private var filterGeneration = 0
    private let faceCache = FaceCache()
    private let illustrationCache = IllustrationCache()
    private let rioCache = RioCache()
    private let qualityCache = QualityCache()
    private var filterPopover: NSPopover?

    /// アプリ終了時に呼ばれ、実行中の顔検出・イラスト判定・画質解析をすぐ打ち切って終了処理をブロックしないようにする。
    func cancelBackgroundWork() {
        faceCache.cancelCurrent()
        illustrationCache.cancelCurrent()
        rioCache.cancelCurrent()
        qualityCache.cancelCurrent()
    }
    private var filterPopoverVC: FilterPopoverViewController?
    private var sortPopover: NSPopover?
    private var sortPopoverVC: SortPopoverViewController?

    private static let thumbSliderItemID = NSToolbarItem.Identifier("thumbSize")
    private static let sortItemID = NSToolbarItem.Identifier("sort")
    private static let filterItemID = NSToolbarItem.Identifier("filter")
    private static let slideshowItemID = NSToolbarItem.Identifier("slideshow")
    private static let rioSortItemID = NSToolbarItem.Identifier("rioSort")
    private static let reloadItemID = NSToolbarItem.Identifier("reload")
    private static let dateBadgeItemID = NSToolbarItem.Identifier("dateBadge")
    private static let sizeBadgeItemID = NSToolbarItem.Identifier("sizeBadge")
    private static let autoplayNextItemID = NSToolbarItem.Identifier("autoplayNext")
    /// 月日/サイズ/動画自動再生バッジ・トグルのボタン(押されている/いないでそれぞれの
    /// Boolを反映する`.pushOnPushOff`ボタン)。各Boolのdidsetから見た目を同期するために
    /// 参照を保持する。
    private weak var dateBadgeButton: NSButton?
    private weak var sizeBadgeButton: NSButton?
    private weak var autoplayNextButton: NSButton?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "MyGallery"
        window.toolbarStyle = .unified
        window.center()
        self.init(window: window)

        if let saved = SortOrder(rawValue: UserDefaults.standard.integer(forKey: defaultsSortKey)) {
            sortOrder = saved
        }
        showDateBadge = UserDefaults.standard.bool(forKey: defaultsDateBadgeKey)
        showSizeBadge = UserDefaults.standard.bool(forKey: defaultsSizeBadgeKey)
        autoplayNextVideo = UserDefaults.standard.bool(forKey: defaultsAutoplayNextKey)
        let savedCell = UserDefaults.standard.double(forKey: defaultsCellKey)
        if savedCell >= Double(minCellSize), savedCell <= Double(maxCellSize) {
            gridVC.cellSize = CGFloat(savedCell)
        }
        gridVC.qualityScoreProvider = { [weak self] item in self?.qualityCache.result(for: item) }

        setupSplitView()
        setupToolbar()
        setupCallbacks()
        window.setFrameAutosaveName("MyGalleryMain")

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

        sidebarVC.onCheckedChanged = { [weak self] in self?.reloadGrid() }

        gridVC.collectionView.onOpen = { [weak self] index in self?.openViewer(at: index) }
        gridVC.collectionView.onDropFolder = { [weak self] url in self?.setRoot(url) }
        gridVC.collectionView.onSelectionChanged = { [weak self] in self?.updateSubtitle() }

        // グリッドの右クリックメニュー(nil ターゲット → レスポンダチェーン経由で self)
        let menu = NSMenu()
        menu.addItem(withTitle: "Finder で表示",
                     action: #selector(revealInFinder(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "コピー", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "回転して保存",
                     action: #selector(rotateAndSave(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "璃央として登録",
                     action: #selector(registerRio(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "ここから璃央の仕分けを始める",
                     action: #selector(startRioSortingFromSelection(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "選択した写真を「璃央」に仕分ける",
                     action: #selector(labelSelectionRio(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "選択した写真を「璃央以外」に仕分ける",
                     action: #selector(labelSelectionOther(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "選択した写真の仕分けを解除",
                     action: #selector(labelSelectionClear(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "ゴミ箱に入れる",
                     action: #selector(trashSelection(_:)), keyEquivalent: "")
        gridVC.collectionView.menu = menu
    }

    // MARK: root / reload

    func setRoot(_ url: URL) {
        closeViewer()
        window?.title = url.lastPathComponent
        gridVC.items = []
        gridVC.setEmptyState("読み込み中…")
        store.setRoot(url)
    }

    private func scanFinished() {
        sidebarVC.setRoot(store.rootNode)
        reloadGrid()
    }

    private func reloadGrid() {
        applyFilter(to: store.photos(checkedPaths: sidebarVC.checkedPaths, order: sortOrder))
    }

    /// 日付範囲フィルターは同期的に適用し、その後 人物→イラスト種類 の順で
    /// (それぞれ有効な場合だけ・未解析の写真がある場合だけ)Vision解析をバックグラウンドで
    /// 順番に走らせてから反映する。2つの解析を直列に繋いでいるのは、同時に大量のVision
    /// リクエストを投げるとFaceCache/IllustrationCache双方が内部でスレッドを食い合って
    /// 進捗表示が競合するのを避けるため。
    private func applyFilter(to base: [PhotoItem]) {
        filterGeneration += 1
        let gen = filterGeneration
        var dateFiltered = currentFilter.dateRange.apply(to: base)
        // 手動仕分けでの絞り込み(静止画のみ・メモリ上の照合だけなので同期で済む)
        if currentFilter.manualFilter != .all {
            let mf = currentFilter.manualFilter
            dateFiltered = dateFiltered.filter { item in
                guard !item.isVideo else { return false }
                let l = ManualLabelStore.shared.label(for: item)
                switch mf {
                case .all: return true
                case .rio: return l == .rio
                case .other: return l == .other
                case .unlabeled: return l == nil
                }
            }
        }
        // 人物/イラスト種類フィルターと画質順ソートは静止画専用(Vision解析・ブレ判定は
        // 動画に適用できない)。これらが有効な間は動画をグリッドから除外する。
        if currentFilter.personFilter != .all || currentFilter.illustrationFilter != .all || currentFilter.rioFilter != .all || sortOrder.showsQuality {
            dateFiltered = dateFiltered.filter { !$0.isVideo }
        }
        applyPersonFilter(to: dateFiltered, gen: gen, baseCount: base.count)
    }

    private func applyPersonFilter(to items: [PhotoItem], gen: Int, baseCount: Int) {
        guard currentFilter.personFilter != .all else {
            applyIllustrationFilter(to: items, gen: gen, baseCount: baseCount)
            return
        }

        let missing = items.filter { faceCache.result(for: $0) == nil }
        guard !missing.isEmpty else {
            applyIllustrationFilter(to: personFiltered(items), gen: gen, baseCount: baseCount)
            return
        }

        filterPopoverVC?.setStatus("顔を検出中… 0 / \(missing.count)")
        faceCache.analyze(missing, progress: { [weak self] done, total in
            guard let self = self, self.filterGeneration == gen else { return }
            self.filterPopoverVC?.setStatus("顔を検出中… \(done) / \(total)")
        }, completion: { [weak self] in
            guard let self = self, self.filterGeneration == gen else { return }
            self.applyIllustrationFilter(to: self.personFiltered(items), gen: gen, baseCount: baseCount)
        })
    }

    private func personFiltered(_ items: [PhotoItem]) -> [PhotoItem] {
        items.filter { item in
            let has = faceCache.result(for: item) ?? false
            switch currentFilter.personFilter {
            case .all: return true
            case .hasPerson: return has
            case .noPerson: return !has
            }
        }
    }

    private func applyIllustrationFilter(to items: [PhotoItem], gen: Int, baseCount: Int) {
        guard currentFilter.illustrationFilter != .all else {
            filterPopoverVC?.setStatus("")
            applyRioFilter(to: items, gen: gen, baseCount: baseCount)
            return
        }

        let missing = items.filter { illustrationCache.result(for: $0) == nil }
        guard !missing.isEmpty else {
            filterPopoverVC?.setStatus("")
            applyRioFilter(to: illustrationFiltered(items), gen: gen, baseCount: baseCount)
            return
        }

        filterPopoverVC?.setStatus("種類を判定中… 0 / \(missing.count)")
        illustrationCache.analyze(missing, progress: { [weak self] done, total in
            guard let self = self, self.filterGeneration == gen else { return }
            self.filterPopoverVC?.setStatus("種類を判定中… \(done) / \(total)")
        }, completion: { [weak self] in
            guard let self = self, self.filterGeneration == gen else { return }
            self.filterPopoverVC?.setStatus("")
            self.applyRioFilter(to: self.illustrationFiltered(items), gen: gen, baseCount: baseCount)
        })
    }

    private func applyRioFilter(to items: [PhotoItem], gen: Int, baseCount: Int) {
        guard currentFilter.rioFilter != .all else {
            applyQualitySort(to: items, gen: gen, baseCount: baseCount)
            return
        }
        guard RioReferenceStore.shared.count > 0 else {
            filterPopoverVC?.setStatus("先に「表示 > 選択中の写真を璃央として登録」で写真を登録してください")
            applyQualitySort(to: items, gen: gen, baseCount: baseCount)
            return
        }
        let missing = items.filter { rioCache.distance(for: $0) == nil }
        guard !missing.isEmpty else {
            filterPopoverVC?.setStatus("")
            applyQualitySort(to: rioFiltered(items), gen: gen, baseCount: baseCount)
            return
        }
        filterPopoverVC?.setStatus("璃央を判定中… 0 / \(missing.count)")
        rioCache.analyze(missing, progress: { [weak self] done, total in
            guard let self = self, self.filterGeneration == gen else { return }
            self.filterPopoverVC?.setStatus("璃央を判定中… \(done) / \(total)")
        }, completion: { [weak self] in
            guard let self = self, self.filterGeneration == gen else { return }
            self.filterPopoverVC?.setStatus("")
            self.applyQualitySort(to: self.rioFiltered(items), gen: gen, baseCount: baseCount)
        })
    }

    private func rioFiltered(_ items: [PhotoItem]) -> [PhotoItem] {
        let th = currentFilter.rioThreshold
        return items.filter { item in
            let isRio = (rioCache.distance(for: item) ?? .infinity) <= th
            return currentFilter.rioFilter == .rio ? isRio : !isRio
        }
    }

    private func illustrationFiltered(_ items: [PhotoItem]) -> [PhotoItem] {
        items.filter { item in
            let isIllust = illustrationCache.result(for: item) ?? false
            switch currentFilter.illustrationFilter {
            case .all: return true
            case .illustrationOnly: return isIllust
            case .photoOnly: return !isIllust
            }
        }
    }

    /// 画質順ソートが選ばれているときだけ、まだ未解析の写真を`QualityCache`でバックグラウンド
    /// 解析してから並び替える(重い処理なので他のソート順では一切走らない)。進捗は
    /// フィルターポップオーバーではなくウインドウのサブタイトルに一時的に出す
    /// (ソートメニューはポップオーバーを開かずに使えるため)。
    private func applyQualitySort(to items: [PhotoItem], gen: Int, baseCount: Int) {
        guard sortOrder.showsQuality else {
            finalizeGrid(items, baseCount: baseCount)
            return
        }

        let missing = items.filter { qualityCache.result(for: $0) == nil }
        guard !missing.isEmpty else {
            finalizeGrid(sortedByQuality(items), baseCount: baseCount)
            return
        }

        window?.subtitle = "画質を解析中… 0 / \(missing.count)"
        qualityCache.analyze(missing, progress: { [weak self] done, total in
            guard let self = self, self.filterGeneration == gen else { return }
            self.window?.subtitle = "画質を解析中… \(done) / \(total)"
        }, completion: { [weak self] in
            guard let self = self, self.filterGeneration == gen else { return }
            self.finalizeGrid(self.sortedByQuality(items), baseCount: baseCount)
        })
    }

    private func sortedByQuality(_ items: [PhotoItem]) -> [PhotoItem] {
        let ascending = sortOrder == .qualityAsc
        return items.sorted { a, b in
            let sa = qualityCache.result(for: a) ?? 0
            let sb = qualityCache.result(for: b) ?? 0
            return ascending ? sa < sb : sa > sb
        }
    }

    private func finalizeGrid(_ items: [PhotoItem], baseCount: Int) {
        currentBaseCount = baseCount
        gridVC.items = items
        if store.rootURL == nil {
            gridVC.setEmptyState(
                "フォルダを開いてください(⌘O)\nウインドウへのフォルダのドロップでも開けます",
                showButton: true)
        } else if gridVC.items.isEmpty {
            let message: String
            if store.isScanning {
                message = "読み込み中…"
            } else if sidebarVC.checkedPaths.isEmpty {
                message = "サイドバーでフォルダにチェックを入れてください"
            } else if baseCount > 0 {
                message = "条件に一致する写真がありません"
            } else {
                message = "写真が見つかりません"
            }
            gridVC.setEmptyState(message)
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
        let unit = "枚"
        let countText = currentFilter.isActive ? "\(n) / \(currentBaseCount) \(unit)" : "\(n) \(unit)"
        window.subtitle = sel > 0 ? "\(countText)(\(sel) \(unit)選択)" : countText
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
            v.onAutoAdvance = { [weak self] in self?.stepViewer(1) }
            v.autoplayNext = autoplayNextVideo
            v.onRegisterRio = { [weak self] fp, key in self?.registerRioPrint(fp, key: key) }
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
        if slideshow.isRunning { slideshow.stop() }
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

    /// ⌘⌫(Finder/Photos.app と同じく確認なしで即ゴミ箱へ。Finder のゴミ箱から復元可能)。
    @objc func trashSelection(_ sender: Any?) {
        let targets = targetPhotos()
        guard !targets.isEmpty else { return }

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
        syncAfterExternalTrash(removed)
        if !failures.isEmpty { showTrashFailureAlert(failures) }
    }

    /// 選択(またはビューア表示中)の写真を 90°時計回りに回転して元のファイルへ直接上書き保存する。
    /// ゴミ箱と違って元に戻せないため、書き込みに対応していない形式(RAW 等)は失敗として報告する。
    @objc func rotateAndSave(_ sender: Any?) {
        let targets = targetPhotos()
        guard !targets.isEmpty else { return }

        var rotated: [PhotoItem] = []
        var failures: [String] = []
        for p in targets {
            if p.isVideo {
                failures.append("\(p.url.lastPathComponent) — 動画は回転に対応していません")
                continue
            }
            switch PhotoRotator.rotateClockwise(url: p.url) {
            case .success:
                rotated.append(p)
            case .failure(let err):
                failures.append("\(p.url.lastPathComponent) — \(err.message)")
            }
        }

        for p in rotated {
            ThumbnailLoader.shared.invalidate(p)
            store.refreshMtime(at: p.url.path)
        }
        if !rotated.isEmpty {
            reloadGrid()
            if viewerVisible, viewerIndex < gridVC.items.count {
                viewer?.show(photo: gridVC.items[viewerIndex], index: viewerIndex, total: gridVC.items.count)
            }
        }
        if !failures.isEmpty {
            let a = NSAlert()
            a.messageText = "回転して保存できなかった写真があります"
            a.informativeText = failures.joined(separator: "\n")
            a.runModal()
        }
    }

    @objc func findDuplicates(_ sender: Any?) {
        guard store.rootURL != nil else { return }
        // 検査対象はサイドバーでチェックしているフォルダの写真だけ(ルート全体ではない)。
        // グリッド側の日付/人物/種類フィルターは掛けない ― 絞り込みはフォルダ単位のみ。
        let scope = store.photos(checkedPaths: sidebarVC.checkedPaths, order: .name)
        guard !scope.isEmpty else { NSSound.beep(); return }
        let scopePaths = Set(scope.map(\.url.path))
        if let existing = duplicatesWC {
            if scopePaths == duplicatesScopePaths {
                existing.window?.makeKeyAndOrderFront(nil)
                return
            }
            // チェックを変えてから開き直した場合は、古い範囲の結果を残さず新しい範囲で検出し直す。
            existing.close()
        }
        let controller = DuplicatesWindowController(photos: scope) { [weak self] removed, failures in
            self?.syncAfterExternalTrash(removed)
            if !failures.isEmpty { self?.showTrashFailureAlert(failures) }
        }
        controller.onClose = { [weak self, weak controller] in
            // 開き直しで先に新しいウインドウが登録されている場合は、それを消さない。
            if self?.duplicatesWC === controller { self?.duplicatesWC = nil }
        }
        duplicatesWC = controller
        duplicatesScopePaths = scopePaths
        controller.showWindow(nil)
    }

    /// 写真がゴミ箱へ移動された後、ストア/サイドバー/グリッド/ビューアを同期させる
    /// (通常のゴミ箱操作・重複検出ウインドウからの削除の両方から呼ばれる)。
    private func syncAfterExternalTrash(_ removed: Set<String>) {
        guard !removed.isEmpty else { return }
        store.removePhotos(withPaths: removed)
        sidebarVC.setRoot(store.rootNode)
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
    }

    private func showTrashFailureAlert(_ failures: [String]) {
        let a = NSAlert()
        a.messageText = "ゴミ箱に入れられなかったファイルがあります"
        a.informativeText = failures.joined(separator: "\n")
        a.runModal()
    }

    @objc func changeSort(_ sender: NSMenuItem) {
        guard let order = SortOrder(rawValue: sender.tag) else { return }
        sortOrder = order
        reloadGrid()
    }

    /// サムネイルの月日バッジ(左上)のオン/オフ(ローカル・OneDriveどちらでも使える
    /// ― `PhotoItem.name`/`mtime`はどちらのソースでも入っているので、サイズ順・
    /// 画質順のようにOneDriveで無効化する理由が無い)。`showDateBadge`のdidSetが
    /// `gridVC.showDateBadge`を更新し、そのdidSetが`reloadData()`するので、
    /// ここでは値を反転するだけでよい。
    @objc func toggleDateBadge(_ sender: Any?) {
        showDateBadge.toggle()
    }

    /// サムネイルのファイルサイズバッジ(右下)のオン/オフ(2026-09-07追加)。
    /// ローカル・OneDriveどちらでも使える(`PhotoItem.fileSize`は両ソースとも
    /// 実値が入っている)。
    @objc func toggleSizeBadge(_ sender: Any?) {
        showSizeBadge.toggle()
    }

    /// 選択中の写真(璃央が主役で写っているもの)から最大の顔を参照として登録する(`RioMatcher.swift`)。
    @objc func registerRio(_ sender: Any?) {
        let photos = targetPhotos().filter { !$0.isVideo }
        guard !photos.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [(key: String, print: VNFeaturePrintObservation)] = []
            for p in photos {
                if let best = RioFaceAnalyzer.facePrints(url: p.url).max(by: { $0.area < $1.area }) {
                    found.append((p.cacheKey, best.print))
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let added = RioReferenceStore.shared.add(found)
                if added > 0 {
                    self.rioCache.reset()
                    if self.currentFilter.rioFilter != .all { self.reloadGrid() }
                }
                let alert = NSAlert()
                alert.messageText = "\(added) 枚を新しく登録しました"
                var info = "選択 \(photos.count) 枚のうち、顔なし \(photos.count - found.count) 枚、登録済みのためスキップ \(found.count - added) 枚。"
                info += "登録済み合計: \(RioReferenceStore.shared.count) 枚。複数人が写っている写真では最も大きい顔が使われます。"
                alert.informativeText = info
                alert.runModal()
            }
        }
    }

    // MARK: 手動仕分け(`SortMode.swift`)

    private var sortOverlay: SortOverlay?

    /// 現在グリッドに出ている静止画のうち未仕分けのものを、Tinder風に1枚ずつ仕分ける。
    /// 先にフィルター(日付・人物あり等)で絞ってから始めると効率的。
    /// 選択中の写真の手動仕分けを後から直す(間違えて仕分けた場合の修正用)。
    private func applyManualLabel(_ label: ManualLabel?) {
        let targets = gridVC.selectedItems.filter { !$0.isVideo }
        guard !targets.isEmpty else { return }
        for t in targets { ManualLabelStore.shared.set(label, for: t) }
        // 仕分けフィルター中は、変更した写真が一覧から外れる/入るので再フィルターする
        if currentFilter.manualFilter != .all { reloadGrid() }
        let name = label == .rio ? "璃央" : (label == .other ? "璃央以外" : "未仕分け")
        window?.subtitle = "\(targets.count) 枚を「\(name)」にしました"
    }

    @objc func labelSelectionRio(_ sender: Any?) { applyManualLabel(.rio) }
    @objc func labelSelectionOther(_ sender: Any?) { applyManualLabel(.other) }
    @objc func labelSelectionClear(_ sender: Any?) { applyManualLabel(nil) }

    @objc func startRioSortingFromSelection(_ sender: Any?) {
        startRioSorting(sender, from: gridVC.selectedItems.first)
    }

    @objc func startRioSorting(_ sender: Any?) {
        startRioSorting(sender, from: nil)
    }

    private func startRioSorting(_ sender: Any?, from start: PhotoItem?) {
        guard let cv = window?.contentView, store.rootURL != nil else { return }
        closeViewer()
        var items = gridVC.items.filter { !$0.isVideo && ManualLabelStore.shared.label(for: $0) == nil }
        // 「ここから」: 選択した写真(以降)から始める。選択写真自体が仕分け済みでも、
        // グリッド上でそれ以降にある未仕分けの写真から始まる。
        if let start, let pos = gridVC.items.firstIndex(of: start) {
            let after = Set(gridVC.items[pos...].map { $0.cacheKey })
            items = items.filter { after.contains($0.cacheKey) }
        }
        guard !items.isEmpty else {
            let a = NSAlert()
            a.messageText = "仕分けする写真がありません"
            a.informativeText = "表示中の写真はすべて仕分け済み(または動画のみ)です。"
            a.runModal()
            return
        }
        let o = SortOverlay(frame: cv.bounds, items: items)
        o.autoresizingMask = [.width, .height]
        o.onExit = { [weak self] in self?.endRioSorting() }
        cv.addSubview(o)
        sortOverlay = o
        window?.makeFirstResponder(o)
    }

    private func endRioSorting() {
        sortOverlay?.removeFromSuperview()
        sortOverlay = nil
        if currentFilter.manualFilter != .all { reloadGrid() }
        window?.makeFirstResponder(gridVC.collectionView)
    }

    /// チェック中のフォルダ内で「璃央以外」に仕分けた写真を、確認の上ゴミ箱へ入れる。
    @objc func trashManualOthers(_ sender: Any?) {
        let targets = store.photos(checkedPaths: sidebarVC.checkedPaths, order: .name)
            .filter { !$0.isVideo && ManualLabelStore.shared.label(for: $0) == .other }
        let a = NSAlert()
        guard !targets.isEmpty else {
            a.messageText = "「璃央以外」に仕分けた写真はありません"
            a.runModal()
            return
        }
        a.messageText = "\(targets.count) 枚の「璃央以外」の写真をゴミ箱に入れますか?"
        a.informativeText = "チェック中のフォルダ内が対象です。ゴミ箱からは元に戻せます。"
        a.addButton(withTitle: "ゴミ箱に入れる")
        a.addButton(withTitle: "キャンセル")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var removed = Set<String>()
        var failures: [String] = []
        for p in targets {
            do {
                try FileManager.default.trashItem(at: p.url, resultingItemURL: nil)
                removed.insert(p.url.path)
            } catch { failures.append(p.url.lastPathComponent) }
        }
        ManualLabelStore.shared.remove(paths: Array(removed))
        syncAfterExternalTrash(removed)
        if !failures.isEmpty { showTrashFailureAlert(failures) }
    }

    @objc func resetManualLabels(_ sender: Any?) {
        let c = ManualLabelStore.shared.counts
        let a = NSAlert()
        a.messageText = "手動仕分けの結果(璃央 \(c.rio) / 璃央以外 \(c.other))をすべて消去しますか?"
        a.informativeText = "写真自体は変更されません。"
        a.addButton(withTitle: "消去")
        a.addButton(withTitle: "キャンセル")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        ManualLabelStore.shared.clear()
        if currentFilter.manualFilter != .all { reloadGrid() }
    }

    /// ビューアで範囲選択した領域の特徴量を登録する(結果はビューアのトーストで知らせる)。
    private func registerRioPrint(_ fp: VNFeaturePrintObservation, key: String) {
        let added = RioReferenceStore.shared.add([(key: key, print: fp)])
        if added > 0 {
            rioCache.reset()
            if currentFilter.rioFilter != .all { reloadGrid() }
            viewer?.showToast("璃央として登録しました(合計 \(RioReferenceStore.shared.count) 枚)")
        } else {
            viewer?.showToast("登録済みの範囲のためスキップしました")
        }
    }

    @objc func resetRioRegistrations(_ sender: Any?) {
        RioReferenceStore.shared.clear()
        rioCache.reset()
        if currentFilter.rioFilter != .all { reloadGrid() }
    }

    /// 通常視聴ビューアでの動画自動連続再生のオン/オフ(2026-09-07追加)。
    @objc func toggleAutoplayNext(_ sender: Any?) {
        autoplayNextVideo.toggle()
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
        case #selector(revealInFinder(_:)), #selector(copy(_:)), #selector(trashSelection(_:)),
             #selector(rotateAndSave(_:)):
            return !targetPhotos().isEmpty
        case #selector(refresh(_:)):
            return store.rootURL != nil
        case #selector(findDuplicates(_:)):
            // 対象はチェック中のフォルダだけなので、何もチェックしていなければ無効。
            return store.rootURL != nil && !sidebarVC.checkedPaths.isEmpty
        case #selector(changeSort(_:)):
            menuItem.state = (menuItem.tag == sortOrder.rawValue) ? .on : .off
            return store.rootURL != nil
        case #selector(toggleDateBadge(_:)):
            menuItem.state = showDateBadge ? .on : .off
            return true
        case #selector(toggleSizeBadge(_:)):
            menuItem.state = showSizeBadge ? .on : .off
            return true
        case #selector(labelSelectionRio(_:)), #selector(labelSelectionOther(_:)),
             #selector(labelSelectionClear(_:)):
            return gridVC.selectedItems.contains { !$0.isVideo }
        case #selector(startRioSorting(_:)), #selector(startRioSortingFromSelection(_:)):
            return store.rootURL != nil && !gridVC.items.isEmpty
        case #selector(trashManualOthers(_:)):
            return store.rootURL != nil && ManualLabelStore.shared.counts.other > 0
        case #selector(resetManualLabels(_:)):
            let c = ManualLabelStore.shared.counts
            return c.rio + c.other > 0
        case #selector(registerRio(_:)):
            return !targetPhotos().isEmpty
        case #selector(resetRioRegistrations(_:)):
            return RioReferenceStore.shared.count > 0
        case #selector(toggleAutoplayNext(_:)):
            menuItem.state = autoplayNextVideo ? .on : .off
            return true
        case #selector(zoomIn(_:)):
            return gridVC.cellSize < maxCellSize
        case #selector(zoomOut(_:)):
            return gridVC.cellSize > minCellSize
        case #selector(startSlideshow(_:)):
            return !gridVC.items.isEmpty
        default:
            return true
        }
    }

    // MARK: toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, Self.reloadItemID, Self.sortItemID, Self.filterItemID,
         Self.dateBadgeItemID, Self.sizeBadgeItemID, Self.autoplayNextItemID,
         Self.slideshowItemID, Self.rioSortItemID, .flexibleSpace, Self.thumbSliderItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.thumbSliderItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "サムネイルサイズ"
            item.paletteLabel = "サムネイルサイズ"
            let s = NSSlider(value: Double(gridVC.cellSize),
                             minValue: Double(minCellSize), maxValue: Double(maxCellSize),
                             target: self, action: #selector(sliderChanged(_:)))
            s.isContinuous = true
            s.widthAnchor.constraint(equalToConstant: 140).isActive = true
            s.toolTip = item.label
            slider = s
            item.view = s
            return item
        }
        if itemIdentifier == Self.reloadItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "再読み込み"
            item.paletteLabel = "再読み込み"
            let button = NSButton(
                image: NSImage(systemSymbolName: "arrow.clockwise",
                               accessibilityDescription: "再読み込み") ?? NSImage(),
                target: self, action: #selector(refresh(_:)))
            button.bezelStyle = .texturedRounded
            // マウスを乗せたら機能名を出す(アイコンだけだと何のボタンか分からないため)。
            button.toolTip = item.label
            item.view = button
            return item
        }
        if itemIdentifier == Self.filterItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "フィルター"
            item.paletteLabel = "フィルター"
            let button = NSButton(
                image: NSImage(systemSymbolName: "line.3.horizontal.decrease.circle",
                               accessibilityDescription: "フィルター") ?? NSImage(),
                target: self, action: #selector(toggleFilterPopover(_:)))
            button.bezelStyle = .texturedRounded
            // マウスを乗せたら機能名を出す(アイコンだけだと何のボタンか分からないため)。
            button.toolTip = item.label
            item.view = button
            return item
        }
        if itemIdentifier == Self.sortItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "並び替え"
            item.paletteLabel = "並び替え"
            let button = NSButton(
                image: NSImage(systemSymbolName: "arrow.up.arrow.down.circle",
                               accessibilityDescription: "並び替え") ?? NSImage(),
                target: self, action: #selector(toggleSortPopover(_:)))
            button.bezelStyle = .texturedRounded
            // マウスを乗せたら機能名を出す(アイコンだけだと何のボタンか分からないため)。
            button.toolTip = item.label
            item.view = button
            return item
        }
        if itemIdentifier == Self.dateBadgeItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "月日を表示"
            item.paletteLabel = "月日を表示"
            let button = NSButton(
                image: NSImage(systemSymbolName: "calendar",
                               accessibilityDescription: "サムネイルに月日を表示") ?? NSImage(),
                target: self, action: #selector(toggleDateBadge(_:)))
            button.bezelStyle = .texturedRounded
            // オン/オフが見た目で分かるトグルボタンにする(メニュー項目のチェックマークと
            // 違い、押した状態が残るボタンが欲しいというユーザー要望への対応、
            // 2026-09-07)。`.pushOnPushOff`はクリックのたびに`state`を`.on`/`.off`で
            // 自動反転するが、ここでは`toggleDateBadge(_:)`側の`showDateBadge`が
            // 真実の状態(source of truth)なので、ボタンの`state`はクリック直後の
            // 自動反転に任せず`showDateBadge`のdidSetで毎回明示的に同期し直す。
            button.setButtonType(.pushOnPushOff)
            button.state = showDateBadge ? .on : .off
            dateBadgeButton = button
            // マウスを乗せたら機能名を出す(アイコンだけだと何のボタンか分からないため)。
            button.toolTip = item.label
            item.view = button
            return item
        }
        if itemIdentifier == Self.sizeBadgeItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "ファイルサイズを表示"
            item.paletteLabel = "ファイルサイズを表示"
            let button = NSButton(
                image: NSImage(systemSymbolName: "scalemass",
                               accessibilityDescription: "サムネイルにファイルサイズを表示") ?? NSImage(),
                target: self, action: #selector(toggleSizeBadge(_:)))
            button.bezelStyle = .texturedRounded
            button.setButtonType(.pushOnPushOff)
            button.state = showSizeBadge ? .on : .off
            sizeBadgeButton = button
            // マウスを乗せたら機能名を出す(アイコンだけだと何のボタンか分からないため)。
            button.toolTip = item.label
            item.view = button
            return item
        }
        if itemIdentifier == Self.autoplayNextItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "動画を自動再生"
            item.paletteLabel = "動画を自動再生"
            let button = NSButton(
                image: NSImage(systemSymbolName: "forward.circle",
                               accessibilityDescription: "動画再生後に次のアイテムへ自動的に進む") ?? NSImage(),
                target: self, action: #selector(toggleAutoplayNext(_:)))
            button.bezelStyle = .texturedRounded
            button.setButtonType(.pushOnPushOff)
            button.state = autoplayNextVideo ? .on : .off
            autoplayNextButton = button
            // マウスを乗せたら機能名を出す(アイコンだけだと何のボタンか分からないため)。
            button.toolTip = item.label
            item.view = button
            return item
        }
        if itemIdentifier == Self.rioSortItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "璃央仕分け"
            item.paletteLabel = "璃央仕分け"
            let button = NSButton(
                image: NSImage(systemSymbolName: "rectangle.stack.badge.person.crop",
                               accessibilityDescription: "璃央仕分け")
                    ?? NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "璃央仕分け")
                    ?? NSImage(),
                target: self, action: #selector(startRioSorting(_:)))
            button.bezelStyle = .texturedRounded
            button.toolTip = "璃央仕分け(→ 璃央 / ← 璃央以外)を始める"
            item.view = button
            return item
        }
        if itemIdentifier == Self.slideshowItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "スライドショー"
            item.paletteLabel = "スライドショー"
            let button = NSButton(
                image: NSImage(systemSymbolName: "play.rectangle",
                               accessibilityDescription: "スライドショー") ?? NSImage(),
                target: self, action: #selector(toggleSlideshowSettingsPopover(_:)))
            button.bezelStyle = .texturedRounded
            // マウスを乗せたら機能名を出す(アイコンだけだと何のボタンか分からないため)。
            button.toolTip = item.label
            item.view = button
            return item
        }
        return nil
    }

    @objc private func toggleSortPopover(_ sender: NSButton) {
        if let pop = sortPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        let vc = sortPopoverVC ?? {
            let vc = SortPopoverViewController()
            vc.onSelect = { [weak self] order in
                guard let self = self else { return }
                self.sortOrder = order
                self.reloadGrid()
                self.sortPopover?.performClose(nil)
            }
            sortPopoverVC = vc
            return vc
        }()
        vc.setSelected(sortOrder)
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        sortPopover = pop
    }

    @objc private func toggleFilterPopover(_ sender: NSButton) {
        if let pop = filterPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        let vc = filterPopoverVC ?? {
            let vc = FilterPopoverViewController()
            vc.onChange = { [weak self] filter in
                guard let self = self else { return }
                self.currentFilter = filter
                self.reloadGrid()
            }
            filterPopoverVC = vc
            return vc
        }()
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        filterPopover = pop
    }

    @objc private func toggleSlideshowSettingsPopover(_ sender: NSButton) {
        if let pop = slideshowSettingsPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        let vc = slideshowSettingsVC ?? {
            let vc = SlideshowSettingsPopoverViewController()
            vc.onStart = { [weak self] in
                self?.slideshowSettingsPopover?.performClose(nil)
                self?.startSlideshow(nil)
            }
            slideshowSettingsVC = vc
            return vc
        }()
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        slideshowSettingsPopover = pop
    }

    /// スライドショーを開始する(ローカル・OneDriveどちらでブラウズ中でも、`gridVC.items`
    /// に現在表示されているものをそのまま対象にする)。
    @objc func startSlideshow(_ sender: Any?) {
        guard !gridVC.items.isEmpty else { return }
        let startIndex = viewerVisible ? viewerIndex
            : (gridVC.firstSelectedIndex ?? 0)
        openViewer(at: startIndex)
        guard let v = viewer else { return }
        slideshow.onIndexChanged = { [weak self] index in self?.viewerIndex = index }
        slideshow.start(overlay: v, window: window, items: gridVC.items, startIndex: startIndex,
                         shuffle: GallerySettings.slideshowShuffleEnabled,
                         photoDuration: GallerySettings.slideshowPhotoDurationSeconds,
                         timeLimitMinutes: GallerySettings.slideshowTimeLimitMinutes,
                         autoFullscreen: GallerySettings.slideshowAutoFullscreen)
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

    func applicationWillTerminate(_ notification: Notification) {
        mainWC?.cancelBackgroundWork()
    }

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
        appMenu.addItem(withTitle: "MyGallery について",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "MyGallery を隠す",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "MyGallery を終了",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "ファイル")
        fileMenu.addItem(withTitle: "フォルダを開く…",
                         action: #selector(MainWindowController.openFolder(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "再読み込み",
                         action: #selector(MainWindowController.refresh(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        let dedupe = NSMenuItem(title: "重複を検出…",
                                action: #selector(MainWindowController.findDuplicates(_:)),
                                keyEquivalent: "d")
        dedupe.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(dedupe)
        fileMenu.addItem(NSMenuItem.separator())
        let reveal = NSMenuItem(title: "Finder で表示",
                                action: #selector(MainWindowController.revealInFinder(_:)),
                                keyEquivalent: "R")
        reveal.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(reveal)
        // Preview.app の「右に回転(⌘R)」と同じキー割り当て(元ファイルへ直接上書き保存)。
        fileMenu.addItem(withTitle: "回転して保存",
                         action: #selector(MainWindowController.rotateAndSave(_:)), keyEquivalent: "r")
        let trash = NSMenuItem(title: "ゴミ箱に入れる",
                               action: #selector(MainWindowController.trashSelection(_:)),
                               keyEquivalent: "\u{08}")
        trash.keyEquivalentModifierMask = [.command]   // Photos.app と同じく ⌘⌫
        fileMenu.addItem(trash)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "閉じる",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        // Edit menu
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "編集")
        // カット/ペーストは、このアプリの他機能としては使わないが、標準セレクタ(cut:/paste:)の
        // メニュー項目が無いと ⌘X/⌘V がテキストフィールド内でも一切効かない(Cocoa の仕様 —
        // フィールドエディタ自身が処理できる操作でも、キー等価物としてメニューに登録されていないと
        // ⌘キー入力がテキスト編集まで届かない)。フォーカスがテキストフィールドにある間は
        // フィールドエディタが自動的にこれらを処理するため、実装(@objc メソッド)は不要。
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー",
                         action: #selector(MainWindowController.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "すべてを選択",
                         action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "表示")
        let sortItem = NSMenuItem(title: "並び替え", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: "並び替え")
        for (title, order) in sortMenuEntries {
            let mi = NSMenuItem(title: title,
                                action: #selector(MainWindowController.changeSort(_:)),
                                keyEquivalent: "")
            mi.tag = order.rawValue
            sortMenu.addItem(mi)
        }
        sortItem.submenu = sortMenu
        viewMenu.addItem(sortItem)
        viewMenu.addItem(withTitle: "サムネイルに月日を表示",
                         action: #selector(MainWindowController.toggleDateBadge(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "サムネイルにファイルサイズを表示",
                         action: #selector(MainWindowController.toggleSizeBadge(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "動画を自動再生",
                         action: #selector(MainWindowController.toggleAutoplayNext(_:)), keyEquivalent: "")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "選択中の写真を璃央として登録",
                         action: #selector(MainWindowController.registerRio(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "璃央の登録をリセット",
                         action: #selector(MainWindowController.resetRioRegistrations(_:)), keyEquivalent: "")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "璃央の仕分けを始める(→璃央 / ←璃央以外)",
                         action: #selector(MainWindowController.startRioSorting(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "「璃央以外」に仕分けた写真をゴミ箱へ…",
                         action: #selector(MainWindowController.trashManualOthers(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "手動仕分けの結果をリセット",
                         action: #selector(MainWindowController.resetManualLabels(_:)), keyEquivalent: "")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "スライドショー開始",
                         action: #selector(MainWindowController.startSlideshow(_:)), keyEquivalent: "")
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
