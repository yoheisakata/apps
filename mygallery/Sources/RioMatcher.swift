import AppKit
import Vision

// 璃央(息子)の写真とそれ以外を分ける機能(2026-11-09)。
//
// Vision には「誰の顔か」を識別する公開APIが無いため、次の方式で近似している:
// ① ユーザーが「璃央が写っている写真」を選んで登録 → 写真内で最大の顔を切り出し、
//    `VNGenerateImageFeaturePrintRequest`の特徴量(feature print)を参照として保存。
// ② フィルター有効時、各写真の全ての顔を同様に特徴量化し、参照との最小距離をキャッシュ。
//    距離が閾値以下なら「璃央あり」。閾値はポップオーバーのスライダーで調整でき、
//    距離をキャッシュしているので調整は再解析なしで即座に反映される。
// feature print は顔認識専用ではなく汎用の画像類似度なので、精度は「顔認識」ほどでは
// ない(特に成長による変化・向き・照明の違い)。登録枚数を増やすほど安定する。

enum RioFilter: Int {
    case all = 0, rio, notRio
}

/// 登録済みの参照特徴量(`~/Library/Application Support/MyGallery/rio-refs.dat`)。
final class RioReferenceStore {
    static let shared = RioReferenceStore()
    private(set) var prints: [VNFeaturePrintObservation] = []
    /// `prints`と同じ並びの登録元写真キー(同じ写真の二重登録を弾く用。旧形式のデータは空文字)。
    private var keys: [String] = []
    private lazy var keysURL = fileURL.deletingLastPathComponent().appendingPathComponent("rio-keys.json")
    private let lock = NSLock()
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyGallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rio-refs.dat")
    }()

    private init() {
        // VNObservation内のtimeRange(CMTimeRange辞書)がセキュア復号のネスト制限に
        // 引っかかって読めない(2026-11-09、再起動で登録が消えた原因)ため、自アプリが
        // 書いたローカルファイルに限り非セキュアで復号する。
        guard let data = try? Data(contentsOf: fileURL),
              let un = try? NSKeyedUnarchiver(forReadingFrom: data) else { return }
        un.requiresSecureCoding = false
        guard let arr = un.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [VNFeaturePrintObservation] else { return }
        prints = arr
        let k = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: keysURL))) ?? []
        keys = k.count == arr.count ? k : Array(repeating: "", count: arr.count)
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return prints.count }

    func snapshot() -> [VNFeaturePrintObservation] { lock.lock(); defer { lock.unlock() }; return prints }

    /// 追加できた件数を返す。同じ写真(キー一致)や、既存の参照とほぼ同一の顔
    /// (距離 < 0.02 ― コピーされた同一写真など)は重複として登録しない。
    @discardableResult
    func add(_ new: [(key: String, print: VNFeaturePrintObservation)]) -> Int {
        lock.lock()
        var added = 0
        for e in new {
            if keys.contains(e.key) { continue }
            let near = prints.contains { r in
                var d: Float = .infinity
                return (try? e.print.computeDistance(&d, to: r)) != nil && d < 0.02
            }
            if near { continue }
            prints.append(e.print); keys.append(e.key); added += 1
        }
        lock.unlock()
        if added > 0 { save() }
        return added
    }

    func clear() {
        lock.lock(); prints = []; keys = []; lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: keysURL)
    }

    private func save() {
        lock.lock(); let p = prints; let k = keys; lock.unlock()
        if let kd = try? JSONEncoder().encode(k) { try? kd.write(to: keysURL, options: .atomic) }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: p as NSArray, requiringSecureCoding: true) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

enum RioFaceAnalyzer {
    /// 写真内の顔ごとの (特徴量, 顔の面積比)。小さすぎる顔(識別に足りない)は除外する。
    static func facePrints(url: URL) -> [(print: VNFeaturePrintObservation, area: CGFloat)] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return [] }
        let faceReq = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([faceReq])
        var out: [(VNFeaturePrintObservation, CGFloat)] = []
        for face in faceReq.results ?? [] {
            let b = face.boundingBox
            guard b.width > 0.04 else { continue }
            if let fp = facePrint(b, in: cg) { out.append((fp, b.width * b.height)) }
        }
        return out
    }

    /// 顔の正規化矩形(Vision座標=左下原点)を、周囲に25%の余白を足して切り出し特徴量化する。
    static func facePrint(_ b: CGRect, in cg: CGImage) -> VNFeaturePrintObservation? {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        var r = CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H)
        r = r.insetBy(dx: -r.width * 0.25, dy: -r.height * 0.25).intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard !r.isEmpty, let crop = cg.cropping(to: r) else { return nil }
        return featurePrint(of: crop)
    }

    static func featurePrint(of cg: CGImage) -> VNFeaturePrintObservation? {
        let req = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        return req.results?.first
    }

    /// ユーザーが写真上で範囲選択した領域(ピクセル座標・左上原点)から参照特徴量を作る。
    /// 範囲内に顔が検出できれば最大の顔を通常の登録と同じ切り出し方で使い(選択が
    /// ゆるくても揃う)、検出できなければ選択範囲そのものを特徴量化する。
    static func regionPrint(cg: CGImage, pixelRect: CGRect) -> VNFeaturePrintObservation? {
        let full = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))
        let r = pixelRect.intersection(full)
        guard r.width >= 8, r.height >= 8, let region = cg.cropping(to: r) else { return nil }
        let faceReq = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: region, options: [:]).perform([faceReq])
        if let face = faceReq.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }), let fp = facePrint(face.boundingBox, in: region) {
            return fp
        }
        return featurePrint(of: region)
    }

    /// 参照との最小距離(顔が無い・参照が無い場合は`.infinity`)。
    static func minDistance(url: URL, refs: [VNFeaturePrintObservation]) -> Float {
        var best = Float.infinity
        for f in facePrints(url: url) {
            for r in refs {
                var d: Float = 0
                if (try? f.print.computeDistance(&d, to: r)) != nil { best = min(best, d) }
            }
        }
        return best
    }
}

/// 写真ごとの「参照との最小距離」キャッシュ(`FaceCache`と同じ並列化・キャンセル方式)。
final class RioCache {
    private var results: [String: Float] = [:]
    private let lock = NSLock()
    private var cancelFlag = CancelFlag()

    func distance(for item: PhotoItem) -> Float? {
        lock.lock(); defer { lock.unlock() }
        return results[key(for: item)]
    }

    /// 参照を追加・削除したら古い距離は無効になる。
    func reset() {
        cancelFlag.cancel()
        lock.lock(); results = [:]; lock.unlock()
    }

    func analyze(_ items: [PhotoItem],
                 progress: @escaping (Int, Int) -> Void,
                 completion: @escaping () -> Void) {
        let total = items.count
        guard total > 0 else { completion(); return }
        cancelFlag.cancel()
        let flag = CancelFlag()
        cancelFlag = flag
        let refs = RioReferenceStore.shared.snapshot()

        DispatchQueue.global(qos: .userInitiated).async {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
            queue.qualityOfService = .userInitiated
            let lock = NSLock()
            var done = 0
            for item in items {
                queue.addOperation {
                    if flag.isCancelled { return }
                    let d = RioFaceAnalyzer.minDistance(url: item.url, refs: refs)
                    if flag.isCancelled { return }   // reset()/再解析後に古い参照での結果を書き込まない
                    self.lock.lock(); self.results[self.key(for: item)] = d; self.lock.unlock()
                    lock.lock(); done += 1; let n = done; lock.unlock()
                    if !flag.isCancelled, n == total || n % 10 == 0 {
                        DispatchQueue.main.async { progress(n, total) }
                    }
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            if !flag.isCancelled { DispatchQueue.main.async { completion() } }
        }
    }

    func cancelCurrent() { cancelFlag.cancel() }

    private func key(for item: PhotoItem) -> String {
        "\(item.url.path)|\(item.mtime.timeIntervalSince1970)"
    }
}
