import SwiftUI

final class ThumbnailLoader: ObservableObject {
    static let shared = ThumbnailLoader()

    private let cacheDir: URL
    private let session: URLSession
    // キャッシュのディスク読み込みはメインを塞がないよう直列キューで行う
    private let cacheQueue = DispatchQueue(label: "thumbnail-cache", qos: .utility)

    @Published var images: [String: NSImage] = [:]
    @Published var matched: Set<String> = []
    @Published private(set) var failedIds: Set<String> = []

    // ダウンロードキュー: 数千タスクを一斉に resume すると接続待ちのまま
    // request timeout で全滅するため、同時 maxConcurrent 件に絞って順に流す。
    // 状態(queue/activeCount 等)の更新はすべてメインスレッドで行う。
    private struct Pending {
        let rom: ScannedROM
        var candidateIndex = 0
        var attempts = 0
    }

    private var queue: [Pending] = []
    private var queuedIds: Set<String> = []
    private var activeCount = 0
    private let maxConcurrent = 6
    private let maxAttempts = 3
    private var backoffUntil: Date?
    private var pumpScheduled = false

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("MyGames/Thumbnails")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func isMatched(_ id: String) -> Bool { matched.contains(id) }
    func isFailed(_ id: String) -> Bool { failedIds.contains(id) }
    func isLoading(_ id: String) -> Bool { queuedIds.contains(id) }

    func loadThumbnail(for rom: ScannedROM) {
        let id = rom.id
        if images[id] != nil || failedIds.contains(id) || queuedIds.contains(id) { return }

        // 候補なし(日本語タイトル等)はリモート照会せず即プレースホルダー扱い
        if rom.thumbnailCandidates.isEmpty {
            failedIds.insert(id)
            return
        }

        queuedIds.insert(id)
        cacheQueue.async { [weak self] in
            guard let self else { return }
            if let cached = self.loadFromCache(id) {
                DispatchQueue.main.async {
                    self.images[id] = cached
                    self.matched.insert(id)
                    self.queuedIds.remove(id)
                }
            } else {
                DispatchQueue.main.async {
                    self.queue.append(Pending(rom: rom))
                    self.pump()
                }
            }
        }
    }

    func loadAll(roms: [ScannedROM]) {
        for rom in roms {
            loadThumbnail(for: rom)
        }
    }

    /// キャッシュ済みサムネイルを時計回りに90°回転し、ディスクにも保存し直す
    /// (リポジトリの画像が横倒しになっているタイトルの向き直し用)
    func rotate(id: String) {
        guard let image = images[id], let rotated = Self.rotated90(image) else { return }
        images[id] = rotated
        cacheQueue.async { [weak self] in
            guard let self else { return }
            if let tiff = rotated.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: self.cacheFile(for: id))
            }
        }
    }

    private static func rotated90(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width
        let h = cg.height
        guard let ctx = CGContext(data: nil, width: h, height: w,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(w))
        ctx.rotate(by: -.pi / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: h, height: w))
    }

    /// ライブラリから削除されたタイトルのメモリ/ディスクキャッシュを破棄する
    func removeCached(ids: Set<String>) {
        for id in ids {
            images.removeValue(forKey: id)
            matched.remove(id)
            failedIds.remove(id)
            queuedIds.remove(id)
            try? FileManager.default.removeItem(at: cacheFile(for: id))
        }
        queue.removeAll { ids.contains($0.rom.id) }
    }

    // MARK: - Download queue

    /// メインスレッド専用。空きスロットがある限りキューからタスクを流す。
    private func pump() {
        if let until = backoffUntil {
            if until > Date() {
                if !pumpScheduled {
                    pumpScheduled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + until.timeIntervalSinceNow + 0.1) { [weak self] in
                        self?.pumpScheduled = false
                        self?.pump()
                    }
                }
                return
            }
            backoffUntil = nil
        }

        while activeCount < maxConcurrent, !queue.isEmpty {
            let item = queue.removeFirst()
            activeCount += 1
            run(item)
        }
    }

    /// 候補名(日本版優先)を順に試す。404 は次候補へ、
    /// タイムアウト・429 等の一時エラーはバックオフ後に再試行する。
    private func run(_ item: Pending) {
        let rom = item.rom
        guard item.candidateIndex < rom.thumbnailCandidates.count else {
            DispatchQueue.main.async {
                self.queuedIds.remove(rom.id)
                self.failedIds.insert(rom.id)
                self.activeCount -= 1
                self.pump()
            }
            return
        }

        let name = rom.thumbnailCandidates[item.candidateIndex]
        guard let url = URL(string: thumbnailURL(repo: rom.system.thumbnailRepo, name: name)) else {
            var next = item
            next.candidateIndex += 1
            run(next)
            return
        }

        let task = session.dataTask(with: url) { [weak self] data, response, _ in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            if status == 200, let data, let image = NSImage(data: data) {
                self.saveToCache(rom.id, data: data)
                DispatchQueue.main.async {
                    self.images[rom.id] = image
                    self.matched.insert(rom.id)
                    self.queuedIds.remove(rom.id)
                    self.activeCount -= 1
                    self.pump()
                }
            } else if status == 404 {
                var next = item
                next.candidateIndex += 1
                self.run(next)
            } else {
                // ネットワークエラー・レート制限など: スロットを返し、後で同じ候補から再開
                DispatchQueue.main.async {
                    self.activeCount -= 1
                    var next = item
                    next.attempts += 1
                    if next.attempts < self.maxAttempts {
                        self.queue.append(next)
                        self.backoffUntil = Date().addingTimeInterval(8)
                    } else {
                        self.queuedIds.remove(rom.id)
                        self.failedIds.insert(rom.id)
                    }
                    self.pump()
                }
            }
        }
        task.resume()
    }

    // MARK: - URL / cache

    private func thumbnailURL(repo: String, name: String) -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "https://raw.githubusercontent.com/libretro-thumbnails/\(repo)/master/Named_Boxarts/\(encoded).png"
    }

    // "-jp" suffix: 日本版優先に切り替えた際、既存の米国版キャッシュを無効化するため
    private func cacheFile(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDir.appendingPathComponent("\(safe)-jp.png")
    }

    private func loadFromCache(_ id: String) -> NSImage? {
        let file = cacheFile(for: id)
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private func saveToCache(_ id: String, data: Data) {
        let file = cacheFile(for: id)
        try? data.write(to: file)
    }
}
