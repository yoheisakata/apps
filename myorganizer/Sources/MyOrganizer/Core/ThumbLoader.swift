import AppKit
import ImageIO

/// 写真サムネイル読み込み(NSCacheでキャッシュするパターン、`VideoThumbLoader`と同じ考え方)。
/// ImageIOのCGImageSourceThumbnailで軽量にデコードする(フル解像度は読まない)。
enum ThumbLoader {
    static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 500
        c.totalCostLimit = 300 << 20 // 約300MB分
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
                    kCGImageSourceThumbnailMaxPixelSize: 320,
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
