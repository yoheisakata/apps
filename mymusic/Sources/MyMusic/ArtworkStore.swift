import AppKit

/// OneDrive の曲のジャケット画像を取ってきてキャッシュする。
/// 画像そのものは曲ファイルに埋め込まれたアートワークで、OneDrive 側が変換して配信してくれる
/// (`OneDriveShareClient.thumbnailURL` 参照 ― こちらで mp3/m4a のタグを解析する必要はない)。
///
/// 曲リストは1000曲を超えることがあるので、**表示されている行のぶんだけ遅延取得する**
/// (`.task(id:)` から `image(for:size:)` を呼ぶ)。取得済みはメモリ(`NSCache`)+
/// ディスク(`~/Library/Caches/MyMusic/artwork/`)にキャッシュし、次回以降はネットワークに出ない。
/// mytube の `Core/ThumbnailStore.swift` と同じ設計(ディスク I/O・デコードは `Task.detached`
/// でメインスレッド外、同時実行数を絞る、失敗はキャッシュして連打を防ぐ)。
@MainActor
final class ArtworkStore {
    static let shared = ArtworkStore()

    /// 用途別のサイズ。行の 32pt サムネイルには `small`(96px)、再生バーの 40pt には
    /// Retina を考えて `medium`(176px)を使う。
    typealias Size = OneDriveShareClient.ThumbnailSize

    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()
    /// 同じ曲への同時リクエストを1本にまとめる(スクロールで `.task` が何度も走るため)。
    /// `NSImage` は macOS 14 未満で `Sendable` でないため、`Task` の結果は `ImageBox` に包む。
    private var inFlight: [String: Task<ImageBox, Never>] = [:]
    /// ジャケットが埋め込まれていない曲(サムネイル取得が 404)を憶えておき、再取得しない。
    /// セッション限りで永続化はしない ― 共有元でアートワークを入れ直した場合に、
    /// アプリを再起動すれば拾い直せるようにするため。
    private var missing: Set<String> = []
    /// 一時的な失敗(通信エラー等)の再試行を10分間抑止する。
    private var failedUntil: [String: Date] = [:]

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MyMusic/artwork", isDirectory: true)
    }()

    private init() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// キャッシュ済みなら即座に返す(ビューの初期表示用。ネットワークには出ない)。
    func cached(for track: Track, size: Size) -> NSImage? {
        guard let key = cacheKey(for: track, size: size) else { return nil }
        return memoryCache.object(forKey: key as NSString)
    }

    /// ジャケットを取得する。メモリ → ディスク → OneDrive の順に探し、見つからなければ
    /// `image == nil`(呼び出し側はプレースホルダーを出す)。戻り値を `ImageBox` にしているのは
    /// `NSImage` が macOS 14 未満で `Sendable` でなく、`async` の戻り値にすると警告になるため。
    func loadImage(for track: Track, size: Size) async -> ImageBox {
        guard let ref = track.oneDrive, let key = cacheKey(for: track, size: size) else { return ImageBox(image: nil) }
        if let cached = memoryCache.object(forKey: key as NSString) { return ImageBox(image: cached) }
        if missing.contains(key) { return ImageBox(image: nil) }
        if let until = failedUntil[key], until > Date() { return ImageBox(image: nil) }
        if let running = inFlight[key] { return await running.value }

        let task = Task<ImageBox, Never> { [cacheDir] in
            let fileURL = cacheDir.appendingPathComponent("\(key).jpg")
            // 1. ディスクキャッシュ
            if let box = await Self.readImage(at: fileURL), box.image != nil {
                return box
            }
            // 2. OneDrive から取得。API 呼び出しと画像取得の両方を `Limiter` の中に入れる
            //(行が一斉に現れたときに、こちらもまとめて何十本も走らせないため)。
            await Limiter.shared.acquire()
            defer { Task { await Limiter.shared.release() } }
            do {
                guard let urlString = try await OneDriveShareClient.thumbnailURL(
                    shareURL: ref.shareURL, driveId: ref.driveId, itemId: ref.itemId, size: size
                ), let url = URL(string: urlString) else {
                    self.markMissing(key)
                    return ImageBox(image: nil)
                }
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                    // アートワークが埋め込まれていない曲。URL は返るが取得は 404 になる。
                    self.markMissing(key)
                    return ImageBox(image: nil)
                }
                let box = await Self.decodeImage(data)
                guard box.image != nil else {
                    self.markMissing(key)
                    return ImageBox(image: nil)
                }
                await Self.writeData(data, to: fileURL)
                return box
            } catch {
                self.markFailed(key)
                return ImageBox(image: nil)
            }
        }
        inFlight[key] = task
        let box = await task.value
        inFlight[key] = nil
        if let image = box.image { memoryCache.setObject(image, forKey: key as NSString) }
        return box
    }

    private func markMissing(_ key: String) { missing.insert(key) }
    private func markFailed(_ key: String) { failedUntil[key] = Date().addingTimeInterval(600) }

    /// ディスクのファイル名にそのまま使えるよう、itemId の記号を潰したキー。
    private func cacheKey(for track: Track, size: Size) -> String? {
        guard let ref = track.oneDrive else { return nil }
        let safeID = ref.itemId.map { $0.isLetterOrDigit ? $0 : "_" }
        return "\(String(safeID))-\(size.rawValue)"
    }

    // MARK: - メインスレッド外で行うファイル I/O とデコード

    /// `NSImage` は macOS 14 未満で `Sendable` に適合しないため、`Task.detached` の外へ
    /// 持ち出すのに薄いラッパーを噛ませる(mytube の `ThumbnailStore` と同じ手当て)。
    struct ImageBox: @unchecked Sendable {
        let image: NSImage?
    }

    private static func readImage(at url: URL) async -> ImageBox? {
        await Task.detached {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImageBox(image: NSImage(data: data))
        }.value
    }

    private static func decodeImage(_ data: Data) async -> ImageBox {
        await Task.detached { ImageBox(image: NSImage(data: data)) }.value
    }

    private static func writeData(_ data: Data, to url: URL) async {
        await Task.detached { try? data.write(to: url) }.value
    }

    /// 画面いっぱいに行が現れたときに、同時リクエストが際限なく増えないようにする。
    private actor Limiter {
        static let shared = Limiter(limit: 4)

        private let limit: Int
        private var active = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) { self.limit = limit }

        func acquire() async {
            if active < limit {
                active += 1
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            if waiters.isEmpty {
                active -= 1
            } else {
                waiters.removeFirst().resume()
            }
        }
    }
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
