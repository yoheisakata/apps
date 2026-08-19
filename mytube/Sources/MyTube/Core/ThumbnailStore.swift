import AppKit
import AVFoundation
import CryptoKit

/// 動画のサムネイル(数秒地点のフレーム)と長さを非同期に取得し、メモリ + ディスクにキャッシュする。
/// ディスクキャッシュのキーはファイルパス+更新日時から作るため、ファイルが変わればキャッシュも自動的に無効化される。
@MainActor
final class ThumbnailStore: ObservableObject {
    static let shared = ThumbnailStore()

    struct ThumbnailResult {
        let image: NSImage?
        let duration: TimeInterval?
    }

    private let memoryCache = NSCache<NSString, NSImage>()
    private let durationCache = NSCache<NSString, NSNumber>()
    private let cacheDir: URL
    private let limiter = ConcurrencyLimiter(limit: 4)
    private var inFlight: [String: Task<ThumbnailResult, Never>] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    /// 生成に失敗したキーはこの時刻まで再試行しない(2026-08-05追加 ― グリッドの
    /// スクロールでセルが再表示されるたびに`.task(id:)`が発火し、失敗を全くキャッシュして
    /// いなかったため、失効したURLや一時的に落ちているリモート動画へのリクエストが際限なく
    /// 繰り返されていた。失敗を10分間キャッシュし、無駄なリトライの連打を防ぐ)。
    private var failedUntil: [String: Date] = [:]
    private static let failureCooldown: TimeInterval = 600

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = base.appendingPathComponent("MyTube/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // 件数上限(400枚)はあくまで保険。実際の枯渇防止は totalCostLimit(バイト単位、
        // 640x360 サムネイル換算で約160枚分)が主。それでも足りない場合に備えて、
        // システムのメモリ逼迫通知を受けたらメモリキャッシュを即座に空にする
        // (ディスクキャッシュは残るので、次回表示時はディスクから再読込するだけで済む)。
        memoryCache.countLimit = 400
        memoryCache.totalCostLimit = 150 * 1024 * 1024

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.memoryCache.removeAllObjects()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func cachedImage(for item: VideoItem) -> NSImage? {
        memoryCache.object(forKey: cacheKey(for: item) as NSString)
    }

    func cachedDuration(for item: VideoItem) -> TimeInterval? {
        durationCache.object(forKey: cacheKey(for: item) as NSString)?.doubleValue
    }

    /// 長さフィルター用に、サムネイル画像は生成せず長さだけを取得する軽量版。
    /// `AVAssetImageGenerator` を使わないためデコードコストが低いが、大量の動画に対して
    /// 呼ばれる想定(フィルター有効時は全動画分)のため、`limiter` でサムネイル生成と
    /// 同時実行数を共有し、システム全体の AVFoundation 負荷を一定に保つ。
    func loadDuration(for item: VideoItem) async -> TimeInterval? {
        let key = cacheKey(for: item)
        if let cached = durationCache.object(forKey: key as NSString) {
            return cached.doubleValue
        }
        // YouTubeはプレイリスト取得時点(`YouTubePlaylistClient`)でyt-dlpのメタデータから
        // 長さが既に分かっているので、未ダウンロードの動画をAVAssetでプロービングしない
        // (`item.url`は再生不可能なwatchページURLのため、そもそも失敗するだけ)。
        if let known = item.knownDurationSeconds {
            durationCache.setObject(NSNumber(value: known), forKey: key as NSString)
            return known
        }
        await limiter.acquire()
        let duration = try? await AVURLAsset(url: item.url).load(.duration).seconds
        await limiter.release()
        guard let duration, duration.isFinite else { return nil }
        durationCache.setObject(NSNumber(value: duration), forKey: key as NSString)
        return duration
    }

    /// 同一動画への同時呼び出しは1つの生成タスクにまとめて重複生成を避ける。
    func load(for item: VideoItem) async -> ThumbnailResult {
        let key = cacheKey(for: item)
        if let image = memoryCache.object(forKey: key as NSString) {
            return ThumbnailResult(image: image, duration: durationCache.object(forKey: key as NSString)?.doubleValue)
        }
        if let until = failedUntil[key], until > Date() {
            return ThumbnailResult(image: nil, duration: nil)
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<ThumbnailResult, Never> { [weak self] in
            guard let self else { return ThumbnailResult(image: nil, duration: nil) }
            return await self.generate(for: item, key: key)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if result.image == nil {
            failedUntil[key] = Date().addingTimeInterval(Self.failureCooldown)
        } else {
            failedUntil[key] = nil
        }
        return result
    }

    private func generate(for item: VideoItem, key: String) async -> ThumbnailResult {
        let start = DispatchTime.now()
        defer {
            // 150ms超はグリッド描画中に体感できる遅さの目安として`.notice`、それ以下は
            // `.debug`(既定では非表示、Console.appで「デバッグメッセージを含める」を
            // 有効にしたときだけ見える)に分けている(2026-08-06、パフォーマンス調査用に追加)。
            let ms = Log.elapsedMs(since: start)
            if ms > 150 {
                Log.thumbnail.notice("生成が遅い: \(item.title, privacy: .public) (\(ms, format: .fixed(precision: 1))ms)")
            } else {
                Log.thumbnail.debug("生成: \(item.title, privacy: .public) (\(ms, format: .fixed(precision: 1))ms)")
            }
        }
        let diskPath = cacheDir.appendingPathComponent("\(key).jpg")

        // OneDriveはサムネイル生成(フレーム抽出)を一切行わない(2026-08-14、
        // 「OneDriveのリンクから動画はサムネイルをDLしないとしたら、パフォーマンスは
        // 上がる?」という質問を受け、「1(サムネイル自体を出さない、最速)でいい」との
        // 回答で対応)。**このチェックは下のディスクキャッシュ読み込みより前に置く必要がある**
        // ― 以前は先にディスクキャッシュを見ていたため、この変更を入れる前に既に生成済みの
        // OneDriveサムネイルがディスクに残っている場合、そちらが優先して読み込まれてしまい
        // 「サムネイルなしにしたはずだけどまだ出てくる」という不具合になっていた。ディスクの
        // 古いキャッシュファイル自体は消していない(孤児化するだけで実害はない)が、
        // このチェックを先頭に置くことで二度と読み込まれなくなる。長さ
        // (`asset.load(.duration)`のみ、通常ファイルヘッダだけで済み軽量)は引き続き取得する。
        if item.remoteKind == .oneDrive, item.thumbnailURL == nil {
            await limiter.acquire()
            let result = await loadDurationOnly(item: item, key: key)
            await limiter.release()
            return result
        }

        // ディスクキャッシュの読み込み(JPEGデコード含む)は`limiter`の外(無制限)だが、
        // `Task.detached`でメインスレッドの外に逃がす(2026-08-05、初回ロードのパフォーマンス
        // 改善 ― `ThumbnailStore`は`@MainActor`なので、素朴に`Data(contentsOf:)`を直接
        // 呼ぶとディスクI/O+JPEGデコードがメインスレッド上で同期的に実行されてしまい、
        // アプリ再起動直後にグリッドへ一斉に表示される数十枚のキャッシュ済みサムネイルを
        // 読み込む際にメインスレッドが詰まってもたつく原因になっていた。ここは既存の
        // ディスクキャッシュを読むだけでメモリ使用量は増えない)。
        if let image = await Self.loadDiskImage(at: diskPath) {
            // 長さフィルターの先読み(`loadDuration`)で既に取得済みなら再取得しない。
            // YouTubeはプレイリスト取得時点で長さが判明済み(`item.knownDurationSeconds`)
            // なので、未ダウンロードでは再生不可能なwatchページURLの`item.url`をAVAssetで
            // プロービングしない(判明済みの値を無視して毎回失敗するだけの無駄な呼び出しを
            // 避ける)。
            let duration: TimeInterval?
            if let cached = durationCache.object(forKey: key as NSString) {
                duration = cached.doubleValue
            } else if let known = item.knownDurationSeconds {
                duration = known
                durationCache.setObject(NSNumber(value: known), forKey: key as NSString)
            } else {
                duration = try? await AVURLAsset(url: item.url).load(.duration).seconds
                if let duration { durationCache.setObject(NSNumber(value: duration), forKey: key as NSString) }
            }
            memoryCache.setObject(image, forKey: key as NSString, cost: memoryCost(of: image))
            return ThumbnailResult(image: image, duration: duration)
        }

        await limiter.acquire()
        // YouTube動画は`thumbnailURL`(公式サムネイル直リンク)が非nil ― `item.url`は
        // 未ダウンロードの間は再生不可能なwatchページURLで、AVAssetImageGeneratorに渡しても
        // フレーム抽出できない(ダウンロード完了後は`item.url`ではなくローカルファイルを
        // `DownloadStore`経由で再生するが、サムネイルは常に公式画像で十分なため、
        // ダウンロード状態に関わらずこちらを使う)。
        // ここに来る時点でOneDrive動画は除外済み(上記の早期return参照)なので、残りは
        // YouTube(公式サムネイル直リンク)かローカル(フレーム抽出)のどちらか。
        let result: ThumbnailResult
        if let thumbnailURL = item.thumbnailURL {
            result = await fetchRemoteThumbnail(thumbnailURL: thumbnailURL, knownDuration: item.knownDurationSeconds, diskPath: diskPath, key: key)
        } else {
            result = await renderAndCache(item: item, diskPath: diskPath, key: key)
        }
        await limiter.release()
        return result
    }

    /// YouTube用: フレーム抽出の代わりに公式サムネイル画像をそのままフェッチする。
    private func fetchRemoteThumbnail(thumbnailURL: URL, knownDuration: TimeInterval?, diskPath: URL, key: String) async -> ThumbnailResult {
        guard let (data, _) = try? await URLSession.shared.data(from: thumbnailURL) else {
            return ThumbnailResult(image: nil, duration: knownDuration)
        }
        // デコード・ディスク書き込みはメインスレッドの外で行う(`loadDiskImage`/`writeJPEG`と
        // 同じ理由)。
        guard let image = await Self.decodeImage(data) else {
            return ThumbnailResult(image: nil, duration: knownDuration)
        }
        memoryCache.setObject(image, forKey: key as NSString, cost: memoryCost(of: image))
        await Self.writeData(data, to: diskPath)
        if let knownDuration {
            durationCache.setObject(NSNumber(value: knownDuration), forKey: key as NSString)
        }
        return ThumbnailResult(image: image, duration: knownDuration)
    }

    private func renderAndCache(item: VideoItem, diskPath: URL, key: String) async -> ThumbnailResult {
        let asset = AVURLAsset(url: item.url)
        guard let durationTime = try? await asset.load(.duration), durationTime.isNumeric else {
            return ThumbnailResult(image: nil, duration: nil)
        }
        let duration = durationTime.seconds

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let requestedSeconds = (duration.isFinite && duration > 0) ? min(duration * 0.25, 5) : 0
        let time = CMTime(seconds: requestedSeconds, preferredTimescale: 600)

        var nsImage: NSImage?
        if let cgImage = try? await generator.image(at: time).image {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            nsImage = image
            // JPEGエンコード+ディスク書き込みもメインスレッドの外で行う(上記
            // `loadDiskImage`と同じ理由 ― 初回生成時にメインスレッドを詰まらせない)。
            await Self.writeJPEG(rep, to: diskPath)
        }

        if let nsImage {
            memoryCache.setObject(nsImage, forKey: key as NSString, cost: memoryCost(of: nsImage))
        }
        durationCache.setObject(NSNumber(value: duration), forKey: key as NSString)
        return ThumbnailResult(image: nsImage, duration: duration)
    }

    /// OneDrive動画用: サムネイル画像は生成せず長さだけ取得する(2026-08-14追加、`generate`の
    /// OneDrive分岐参照)。`AVAssetImageGenerator`によるフレーム抽出(ネットワーク越しの部分
    /// 読み込み+デコードを伴う)を行わないため、`renderAndCache`よりずっと軽量。
    private func loadDurationOnly(item: VideoItem, key: String) async -> ThumbnailResult {
        guard let durationTime = try? await AVURLAsset(url: item.url).load(.duration), durationTime.isNumeric else {
            return ThumbnailResult(image: nil, duration: nil)
        }
        let duration = durationTime.seconds
        durationCache.setObject(NSNumber(value: duration), forKey: key as NSString)
        return ThumbnailResult(image: nil, duration: duration)
    }

    /// `NSImage`は`Sendable`適合がmacOS 14+限定(このアプリは`.macOS(.v13)`が最低ライン)なため、
    /// `Task.detached`のクロージャから直接返すとSendable警告が出る。単に`Task.detached`を
    /// またいで受け渡すだけで複数スレッドから同時にmutateすることは無いので安全 ―
    /// `@unchecked Sendable`な薄いボックスで包んで警告を抑える。
    private struct ImageBox: @unchecked Sendable {
        let image: NSImage
    }

    /// ディスクキャッシュの読み込み+JPEGデコードを`Task.detached`で行う。`ThumbnailStore`
    /// 自体は`@MainActor`だが、`Task.detached`のクロージャは呼び出し元のアクターと無関係な
    /// スレッドで実行されるため、ここだけは確実にメインスレッドの外で動く。
    private static func loadDiskImage(at path: URL) async -> NSImage? {
        await Task.detached(priority: .utility) { () -> ImageBox? in
            guard let data = try? Data(contentsOf: path), let image = NSImage(data: data) else { return nil }
            return ImageBox(image: image)
        }.value?.image
    }

    /// JPEGエンコード+ディスク書き込みを`Task.detached`で行う(上記`loadDiskImage`と同じ理由)。
    private static func writeJPEG(_ rep: NSBitmapImageRep, to path: URL) async {
        await Task.detached(priority: .utility) {
            guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { return }
            try? jpegData.write(to: path)
        }.value
    }

    /// 画像デコードを`Task.detached`で行う(`fetchRemoteThumbnail`用、上記と同じ理由)。
    private static func decodeImage(_ data: Data) async -> NSImage? {
        await Task.detached(priority: .utility) { () -> ImageBox? in
            guard let image = NSImage(data: data) else { return nil }
            return ImageBox(image: image)
        }.value?.image
    }

    /// 既にネットワークから取得済みのデータをディスクへ書き込むだけ(`fetchRemoteThumbnail`用)。
    private static func writeData(_ data: Data, to path: URL) async {
        await Task.detached(priority: .utility) {
            try? data.write(to: path)
        }.value
    }

    /// デコード後のビットマップの概算バイト数(幅 x 高さ x 4バイト/ピクセル)。
    /// `totalCostLimit` に渡す実コストとして使い、枚数ではなく実際のメモリ使用量で上限管理する。
    private func memoryCost(of image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 0 }
        return rep.pixelsWide * rep.pixelsHigh * 4
    }

    /// リモート動画(`VideoItem.remoteID`が非nil)は`url`(`@content.downloadUrl`)自体が
    /// トークン再発行のたびにクエリ文字列(署名)だけ変わってしまい、`.path`も
    /// `_layouts/15/download.aspx`のような全ファイル共通のパスにしかならないため、
    /// キャッシュキーとして使えない。代わりにOneDrive側の安定したアイテムIDを使う。
    private func cacheKey(for item: VideoItem) -> String {
        let mtime = item.modifiedDate?.timeIntervalSince1970 ?? 0
        let identity = item.remoteID ?? item.url.path
        let raw = "\(identity)|\(mtime)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
