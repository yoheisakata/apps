import Foundation
import ImageIO
import CoreGraphics

/// dHash のハミング距離のしきい値。DupPhotosViewModel(重複写真パイン)と
/// SimilarityIndex(誤配置修正の類似写真フォールバック)の両方で使う共通のしきい値定義。
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
    /// dHash のハミング距離のしきい値（重複写真パインでの exact はバイト単位比較に特殊扱いされるため
    /// この値は使われない。SimilarityIndex では常にdHash距離で比較するため、exact=0はそのまま
    /// 「見た目が完全一致(距離0)」の意味になる）
    var threshold: Int {
        switch self {
        case .exact: return 0
        case .strict: return 2
        case .normal: return 5
        case .loose: return 9
        }
    }
}

/// 知覚ハッシュ(dHash)。DupPhotosViewModel(重複写真検出)とSimilarityIndex
/// (誤配置修正の類似写真フォールバック)の両方から使う共通ロジック。
enum PerceptualHash {
    /// 9x8 グレースケールに縮小し、隣接ピクセルの明暗で 64bit の知覚ハッシュを作る
    static func dHash(source: CGImageSource) -> UInt64? {
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

    static func dHash(of url: URL) -> UInt64? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return dHash(source: src)
    }
}
