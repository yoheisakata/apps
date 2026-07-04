import SwiftUI
import AppKit
import UniformTypeIdentifiers
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

enum MatchLevel: Int, CaseIterable, Identifiable {
    case exact = 0, strict, normal, loose
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .exact: return "完全一致"
        case .strict: return "厳密"
        case .normal: return "標準"
        case .loose: return "ゆるい"
        }
    }
    /// dHash のハミング距離のしきい値（exact はバイト単位比較）
    var threshold: Int {
        switch self {
        case .exact: return 0
        case .strict: return 2
        case .normal: return 5
        case .loose: return 9
        }
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

// MARK: - エンジン

final class Engine: ObservableObject {
    @Published var folders: [URL] = []
    @Published var photos: [Photo] = []
    @Published var groups: [DupGroup] = []
    @Published var selection: Set<UUID> = []
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

    private var shaCache: [URL: String] = [:]
    private var cancelRequested = false
    private let workQueue = DispatchQueue(label: "dupphotos.work", qos: .userInitiated)

    static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
        "arw", "cr2", "cr3", "nef", "raf", "orf", "dng", "pef", "rw2",
    ]

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
        guard let hash = dHash(source: src) else { return nil }
        return Photo(url: url,
                     fileSize: Int64(size),
                     modDate: values.contentModificationDate ?? Date(),
                     pixelWidth: width, pixelHeight: height,
                     dhash: hash)
    }

    /// 9x8 グレースケールに縮小し、隣接ピクセルの明暗で 64bit の知覚ハッシュを作る
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
                if pixels[row * w + col] < pixels[row * w + col + 1] {
                    hash |= 1
                }
            }
        }
        return hash
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
            let sorted = result.sorted { $0.wastedBytes > $1.wastedBytes }
            DispatchQueue.main.async {
                self.groups = sorted
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
            var byHash: [String: [Photo]] = [:]
            for p in candidates {
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

    /// keepRule に従って各グループの「残す1枚」以外を選択する
    func autoSelect() {
        var sel: Set<UUID> = []
        for group in groups {
            guard let keeper = keeper(in: group) else { continue }
            for p in group.photos where p.id != keeper.id {
                sel.insert(p.id)
            }
        }
        selection = sel
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

    func toggle(_ photo: Photo) {
        if selection.contains(photo.id) {
            selection.remove(photo.id)
        } else {
            selection.insert(photo.id)
        }
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
        selection = []
        statusMessage = "\(moved) 枚をゴミ箱へ移動しました（\(Self.format(bytes: movedBytes)) を回収）"
        if !failed.isEmpty {
            errorMessage = "移動できなかったファイル: " + failed.prefix(5).joined(separator: ", ")
                + (failed.count > 5 ? " ほか \(failed.count - 5) 件" : "")
        }
        autoSelect()
    }

    static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// concurrentPerform 用のスレッドセーフなカウンタ
final class Counter {
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
    static let cache = NSCache<NSURL, NSImage>()

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
                    cache.setObject(img, forKey: url as NSURL)
                    result = img
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// MARK: - アプリ

@main
struct DupPhotosApp: App {
    @StateObject private var engine = Engine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
        }
        .defaultSize(width: 1080, height: 700)
    }
}

// MARK: - メインビュー

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @State private var dropTargeted = false
    @State private var confirmingTrash = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if engine.isWorking {
                ProgressView(value: engine.progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Divider()
            content
            Divider()
            bottomBar
        }
        .navigationTitle("DupPhotos")
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dropTargeted ? Color.accentColor : Color.clear, lineWidth: 3)
                .padding(3)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    }
                    if let url {
                        DispatchQueue.main.async { engine.addFolders([url]) }
                    }
                }
            }
            return true
        }
        .alert("エラー", isPresented: Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(engine.errorMessage ?? "")
        }
        .confirmationDialog(
            "\(engine.selectedPhotos.count) 枚（\(Engine.format(bytes: engine.selectedBytes))）をゴミ箱へ移動しますか？",
            isPresented: $confirmingTrash
        ) {
            Button("ゴミ箱へ移動", role: .destructive) { engine.trashSelected() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("完全には削除されません。ゴミ箱から復元できます。")
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    engine.openPanel()
                } label: {
                    Label("フォルダを追加", systemImage: "folder.badge.plus")
                }
                .disabled(engine.isWorking)

                if engine.isWorking {
                    Button("キャンセル") { engine.cancel() }
                } else {
                    Button {
                        engine.scan()
                    } label: {
                        Label("スキャン", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.folders.isEmpty)
                }

                Picker("マッチレベル", selection: $engine.matchLevel) {
                    ForEach(MatchLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(engine.isWorking)

                Picker("", selection: $engine.keepRule) {
                    ForEach(KeepRule.allCases) { rule in
                        Text(rule.label).tag(rule)
                    }
                }
                .fixedSize()
                .disabled(engine.isWorking)

                Spacer()
            }
            if !engine.folders.isEmpty {
                HStack(spacing: 6) {
                    ForEach(engine.folders, id: \.self) { folder in
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                            Text(folder.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Button {
                                engine.removeFolder(folder)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .disabled(engine.isWorking)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .help(folder.path)
                    }
                    Spacer()
                }
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        if engine.groups.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: engine.folders.isEmpty ? "photo.on.rectangle.angled" : "checkmark.circle")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text(engine.folders.isEmpty
                     ? "写真の入ったフォルダをドラッグ＆ドロップ\nまたは「フォルダを追加」で選択してください"
                     : (engine.statusMessage.isEmpty ? "「スキャン」を押すと重複写真を探します" : engine.statusMessage))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(engine.groups.enumerated()), id: \.element.id) { index, group in
                        GroupSection(group: group, number: index + 1)
                    }
                }
                .padding(12)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(engine.statusMessage)
                .foregroundColor(.secondary)
                .font(.callout)
            Spacer()
            Button("自動選択をやり直す") {
                engine.autoSelect()
            }
            .disabled(engine.groups.isEmpty)
            Button(role: .destructive) {
                confirmingTrash = true
            } label: {
                Label("選択した \(engine.selectedPhotos.count) 枚をゴミ箱へ（\(Engine.format(bytes: engine.selectedBytes))）",
                      systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(engine.selection.isEmpty || engine.isWorking)
        }
        .padding(10)
    }
}

// MARK: - グループ表示

struct GroupSection: View {
    @EnvironmentObject var engine: Engine
    let group: DupGroup
    let number: Int

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("グループ \(number)")
                    .font(.headline)
                Text(group.isExact ? "完全一致" : "類似")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(group.isExact ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
                Text("\(group.photos.count) 枚 · 最大 \(Engine.format(bytes: group.wastedBytes)) 節約可能")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(group.photos) { photo in
                    PhotoCell(photo: photo, selected: engine.selection.contains(photo.id))
                        .onTapGesture { engine.toggle(photo) }
                        .contextMenu {
                            Button("Finder で表示") {
                                NSWorkspace.shared.activateFileViewerSelecting([photo.url])
                            }
                            Button("開く") {
                                NSWorkspace.shared.open(photo.url)
                            }
                        }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct PhotoCell: View {
    let photo: Photo
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    }
                }
                .frame(width: 150, height: 120)
                .clipped()
                .cornerRadius(6)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? .red : .white)
                    .shadow(radius: 2)
                    .padding(5)
            }
            Text(photo.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(photo.pixelWidth)×\(photo.pixelHeight) · \(Engine.format(bytes: photo.fileSize))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 150)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.red.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.red : Color.clear, lineWidth: 2)
        )
        .help(photo.url.path)
        .onAppear {
            if image == nil {
                ThumbLoader.load(photo.url) { image = $0 }
            }
        }
    }
}
