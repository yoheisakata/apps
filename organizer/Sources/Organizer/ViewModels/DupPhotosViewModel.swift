import SwiftUI
import AppKit
import ImageIO
import CryptoKit

// MARK: - モデル

struct Photo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let fileSize: Int64
    let modDate: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let dhash: UInt64

    var resolution: Int { pixelWidth * pixelHeight }
    var name: String { url.lastPathComponent }
}

struct DupGroup: Identifiable {
    let id = UUID()
    var photos: [Photo]
    var isExact: Bool

    /// グループ内で重複している分のサイズ（最大の1枚を残した場合に節約できる量）
    var wastedBytes: Int64 {
        let total = photos.reduce(0) { $0 + $1.fileSize }
        let biggest = photos.map(\.fileSize).max() ?? 0
        return total - biggest
    }
}

enum KeepRule: String, CaseIterable, Identifiable {
    case highestResolution, largestFile, newest, oldest
    var id: String { rawValue }
    var label: String {
        switch self {
        case .highestResolution: return "解像度が最大のものを残す"
        case .largestFile: return "ファイルサイズが最大のものを残す"
        case .newest: return "最新のものを残す"
        case .oldest: return "最古のものを残す"
        }
    }
}

// MARK: - Union-Find

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

// MARK: - ViewModel

final class DupPhotosViewModel: ObservableObject {
    @Published var folders: [URL] = []
    @Published var photos: [Photo] = []
    @Published var groups: [DupGroup] = []
    @Published var selection: Set<UUID> = []
    /// 削除対象として扱う(=チェックの入った)グループのid。外したグループは自動選択の対象外になり、
    /// 個々の写真も手動選択できない(誤検出グループを丸ごと除外できるようにするため)。
    @Published var enabledGroups: Set<UUID> = []
    @Published var isWorking = false
    @Published var progress: Double = 0
    @Published var progressText = ""
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var matchLevel: MatchLevel = .exact {
        didSet { if !photos.isEmpty { regroup() } }
    }
    @Published var keepRule: KeepRule = .highestResolution {
        didSet { autoSelect() }
    }
    /// 1グループあたり削除対象にできる枚数の上限。「ゆるい」等の緩いマッチレベルで
    /// 誤って大きくクラスタリングされたグループを、自動選択(・手動選択)から丸ごと
    /// 大量削除してしまわないための安全策(既定3枚、`toggle`でも同じ上限を守る)。
    @Published var maxDeletePerGroup: Int {
        didSet {
            UserDefaults.standard.set(maxDeletePerGroup, forKey: "dupPhotos.maxDeletePerGroup")
            autoSelect()
        }
    }

    private var shaCache: [URL: String] = [:]
    private var cancelRequested = false
    private let workQueue = DispatchQueue(label: "organizer.dupphotos.work", qos: .userInitiated)

    static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
        "arw", "cr2", "cr3", "nef", "raf", "orf", "dng", "pef", "rw2",
    ]

    private static let defaultMaxDeletePerGroup = 3

    init() {
        let saved = UserDefaults.standard.integer(forKey: "dupPhotos.maxDeletePerGroup")
        maxDeletePerGroup = saved > 0 ? saved : Self.defaultMaxDeletePerGroup
    }

    // MARK: フォルダ

    func addFolders(_ urls: [URL]) {
        for url in urls {
            let std = url.standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: std.path, isDirectory: &isDir),
                  isDir.boolValue,
                  !folders.contains(std) else { continue }
            folders.append(std)
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "追加"
        if panel.runModal() == .OK {
            addFolders(panel.urls)
        }
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
    }

    // MARK: スキャン

    func cancel() { cancelRequested = true }

    func scan() {
        guard !isWorking, !folders.isEmpty else { return }
        isWorking = true
        cancelRequested = false
        progress = 0
        progressText = "ファイルを探しています…"
        statusMessage = ""
        photos = []
        groups = []
        selection = []
        shaCache = [:]
        let folders = self.folders

        workQueue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            var urls: [URL] = []
            for folder in folders {
                let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in e {
                    if self.cancelRequested { break }
                    if Self.imageExts.contains(url.pathExtension.lowercased()) {
                        urls.append(url)
                    }
                }
            }
            if self.cancelRequested {
                DispatchQueue.main.async { self.finishCancelled() }
                return
            }

            let total = urls.count
            DispatchQueue.main.async { self.progressText = "0 / \(total) 枚を解析中…" }

            var results = [Photo?](repeating: nil, count: total)
            let counter = Counter()
            results.withUnsafeMutableBufferPointer { buf -> Void in
                DispatchQueue.concurrentPerform(iterations: total) { i in
                    if self.cancelRequested { return }
                    buf[i] = Self.analyze(url: urls[i])
                    let done = counter.increment()
                    if done % 25 == 0 || done == total {
                        DispatchQueue.main.async {
                            self.progress = Double(done) / Double(max(1, total))
                            self.progressText = "\(done) / \(total) 枚を解析中…"
                        }
                    }
                }
            }
            if self.cancelRequested {
                DispatchQueue.main.async { self.finishCancelled() }
                return
            }
            let photos = results.compactMap { $0 }
            DispatchQueue.main.async {
                self.photos = photos
                self.regroup()
            }
        }
    }

    private func finishCancelled() {
        isWorking = false
        progressText = ""
        statusMessage = "キャンセルしました"
    }

    /// 1枚の画像からサイズ・日付・寸法・dHash を取り出す
    private static func analyze(url: URL) -> Photo? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        var width = 0, height = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }
        guard let hash = PerceptualHash.dHash(source: src) else { return nil }
        return Photo(url: url,
                     fileSize: Int64(size),
                     modDate: values.contentModificationDate ?? Date(),
                     pixelWidth: width, pixelHeight: height,
                     dhash: hash)
    }

    // MARK: グループ化

    func regroup() {
        guard !photos.isEmpty else {
            groups = []
            selection = []
            isWorking = false
            progressText = ""
            return
        }
        cancelRequested = false
        isWorking = true
        progressText = "グループ化しています…"
        let photos = self.photos
        let level = self.matchLevel

        workQueue.async { [weak self] in
            guard let self else { return }
            let result: [DupGroup]
            if level == .exact {
                result = self.groupExact(photos)
            } else {
                result = self.groupSimilar(photos, threshold: level.threshold)
            }
            if self.cancelRequested {
                DispatchQueue.main.async { self.finishCancelled() }
                return
            }
            let sorted = result.sorted { $0.wastedBytes > $1.wastedBytes }
            DispatchQueue.main.async {
                self.groups = sorted
                self.enabledGroups = Set(sorted.map(\.id))
                self.isWorking = false
                self.progress = 1
                self.progressText = ""
                let dupCount = sorted.reduce(0) { $0 + $1.photos.count - 1 }
                self.statusMessage = sorted.isEmpty
                    ? "重複は見つかりませんでした（\(photos.count) 枚を検査）"
                    : "\(sorted.count) グループ・重複 \(dupCount) 枚が見つかりました"
                self.autoSelect()
            }
        }
    }

    /// バイト単位の完全一致（サイズ → SHA256 の二段階）
    private func groupExact(_ photos: [Photo]) -> [DupGroup] {
        var bySize: [Int64: [Photo]] = [:]
        for p in photos { bySize[p.fileSize, default: []].append(p) }
        var groups: [DupGroup] = []
        for (_, candidates) in bySize where candidates.count > 1 {
            if cancelRequested { break }
            var byHash: [String: [Photo]] = [:]
            for p in candidates {
                if cancelRequested { break }
                guard let sha = sha256(of: p.url) else { continue }
                byHash[sha, default: []].append(p)
            }
            for (_, members) in byHash where members.count > 1 {
                groups.append(DupGroup(photos: members.sorted { $0.modDate < $1.modDate }, isExact: true))
            }
        }
        return groups
    }

    /// dHash のハミング距離によるクラスタリング
    private func groupSimilar(_ photos: [Photo], threshold: Int) -> [DupGroup] {
        let n = photos.count
        var uf = UnionFind(n)
        for i in 0..<n {
            if cancelRequested { break }
            let hi = photos[i].dhash
            for j in (i + 1)..<n {
                if (hi ^ photos[j].dhash).nonzeroBitCount <= threshold {
                    uf.union(i, j)
                }
            }
        }
        var clusters: [Int: [Photo]] = [:]
        for i in 0..<n {
            clusters[uf.find(i), default: []].append(photos[i])
        }
        var groups: [DupGroup] = []
        for (_, members) in clusters where members.count > 1 {
            // 完全一致かどうかをラベル付け（同サイズなら SHA まで確認）
            let sizes = Set(members.map(\.fileSize))
            var exact = false
            if sizes.count == 1 {
                let shas = Set(members.compactMap { sha256(of: $0.url) })
                exact = shas.count == 1
            }
            groups.append(DupGroup(photos: members.sorted { $0.modDate < $1.modDate }, isExact: exact))
        }
        return groups
    }

    private let shaLock = NSLock()

    private func sha256(of url: URL) -> String? {
        shaLock.lock()
        if let cached = shaCache[url] { shaLock.unlock(); return cached }
        shaLock.unlock()
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            let data = autoreleasepool { fh.readData(ofLength: 4 << 20) }
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        shaLock.lock()
        shaCache[url] = sha
        shaLock.unlock()
        return sha
    }

    // MARK: 選択

    /// keepRule に従って各グループの「残す1枚」以外を選択する(チェックを外したグループは対象外)
    func autoSelect() {
        var sel: Set<UUID> = []
        for group in groups where enabledGroups.contains(group.id) {
            sel.formUnion(autoSelectIDs(for: group))
        }
        selection = sel
    }

    /// グループ単位の「このグループの重複を削除するか」チェックボックス用。
    /// オフにするとそのグループの写真は選択から外れ、手動選択もできなくする。
    /// オンに戻すとkeepRuleに従って再度自動選択する。
    func setGroupEnabled(_ group: DupGroup, enabled: Bool) {
        if enabled {
            enabledGroups.insert(group.id)
            selection.formUnion(autoSelectIDs(for: group))
        } else {
            enabledGroups.remove(group.id)
            selection.subtract(group.photos.map(\.id))
        }
    }

    func enableAllGroups() {
        enabledGroups = Set(groups.map(\.id))
        autoSelect()
    }

    func disableAllGroups() {
        enabledGroups = []
        selection = []
    }

    private func autoSelectIDs(for group: DupGroup) -> Set<UUID> {
        guard let keeper = keeper(in: group) else { return [] }
        let candidates = group.photos.filter { $0.id != keeper.id }
        return Set(candidates.prefix(maxDeletePerGroup).map(\.id))
    }

    private func keeper(in group: DupGroup) -> Photo? {
        switch keepRule {
        case .highestResolution:
            return group.photos.max { ($0.resolution, $0.fileSize) < ($1.resolution, $1.fileSize) }
        case .largestFile:
            return group.photos.max { $0.fileSize < $1.fileSize }
        case .newest:
            return group.photos.max { $0.modDate < $1.modDate }
        case .oldest:
            return group.photos.min { $0.modDate < $1.modDate }
        }
    }

    /// グループごとの上限(maxDeletePerGroup)を守りながら選択をトグルする。既に上限まで
    /// 選択済みのグループでは、新規の選択追加を拒否する(既存の選択解除は常に許可)。
    func toggle(_ photo: Photo) {
        if selection.contains(photo.id) {
            selection.remove(photo.id)
            return
        }
        if let group = groups.first(where: { g in g.photos.contains { $0.id == photo.id } }) {
            let selectedInGroup = group.photos.filter { selection.contains($0.id) }.count
            guard selectedInGroup < maxDeletePerGroup else {
                statusMessage = "1グループあたり削除対象にできるのは最大\(maxDeletePerGroup)枚までです"
                return
            }
        }
        selection.insert(photo.id)
    }

    var selectedPhotos: [Photo] {
        groups.flatMap(\.photos).filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedPhotos.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: 削除（ゴミ箱へ移動）

    func trashSelected() {
        let targets = selectedPhotos
        guard !targets.isEmpty else { return }
        let fm = FileManager.default
        var moved = 0
        var movedBytes: Int64 = 0
        var failed: [String] = []
        for photo in targets {
            do {
                try fm.trashItem(at: photo.url, resultingItemURL: nil)
                moved += 1
                movedBytes += photo.fileSize
            } catch {
                failed.append(photo.name)
            }
        }
        let trashedIDs = Set(targets.prefix(moved).map(\.id))
        photos.removeAll { trashedIDs.contains($0.id) }
        // グループから取り除き、1枚以下になったグループは解散
        var newGroups: [DupGroup] = []
        for var g in groups {
            g.photos.removeAll { selection.contains($0.id) && !failed.contains($0.name) }
            if g.photos.count > 1 { newGroups.append(g) }
        }
        groups = newGroups
        enabledGroups = enabledGroups.intersection(newGroups.map(\.id))
        selection = []
        statusMessage = "\(moved) 枚をゴミ箱へ移動しました（\(ByteFmt.string(movedBytes)) を回収）"
        if !failed.isEmpty {
            errorMessage = "移動できなかったファイル: " + failed.prefix(5).joined(separator: ", ")
                + (failed.count > 5 ? " ほか \(failed.count - 5) 件" : "")
        }
        autoSelect()
    }
}

/// concurrentPerform 用のスレッドセーフなカウンタ
private final class Counter {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

// MARK: - サムネイル

enum ThumbLoader {
    static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 1000
        c.totalCostLimit = 300 << 20 // 約300MB分(256pxデコード済みビットマップのRGBAサイズをコストとして計上)
        return c
    }()

    static func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let img = cache.object(forKey: url as NSURL) {
            completion(img)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var result: NSImage?
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                ]
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    let cost = cg.width * cg.height * 4
                    cache.setObject(img, forKey: url as NSURL, cost: cost)
                    result = img
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
