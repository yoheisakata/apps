import Foundation
import ImageIO

/// 写真整理で「整理先に同名ファイルが既にあり、MD5は違う」ときの判定。
/// 同じ秒に撮った連写は同名になるため、まず見た目(dHash+縦横比)で同じ写真かを確かめ、
/// 同じ写真のときだけ画質(画素数→同画素数ならファイルサイズ)を比べる。
enum ImageQuality {
    enum Verdict {
        case differentPhoto        // 別の写真 → 従来どおり _N を付けて追加
        case sourceBetter(String)  // 同じ写真でソースの方が高画質 → 整理先を置き換える
        case sameOrWorse(String)   // 同じ写真で画質がほぼ同じ/整理先の方が上 → スキップしてソース削除
    }

    struct Info {
        let width: Int
        let height: Int
        let fileSize: Int64
        let dHash: UInt64
        var pixels: Int { width * height }
        var label: String { "\(width)x\(height) \(ByteFmt.string(fileSize))" }
    }

    /// 同じ写真とみなす dHash ハミング距離(再圧縮・縮小程度のずれを許容し、連写の別カットは弾く)
    static let sameThreshold = MatchLevel.strict.threshold
    /// これを超えて画素数が多ければ「ソースの方が高画質」
    static let pixelRatio = 1.05
    /// 画素数がほぼ同じとき、ファイルサイズがこれを超えて大きければ「高画質」(圧縮率が低い)
    static let sizeRatio = 1.2

    static func info(of url: URL) -> Info? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              let hash = PerceptualHash.dHash(source: src) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return Info(width: w, height: h, fileSize: size, dHash: hash)
    }

    static func compare(source: URL, dest: URL) -> Verdict {
        guard let s = info(of: source), let d = info(of: dest) else { return .differentPhoto }

        // 縦横比(回転を無視するため長辺/短辺)が違えばトリミング等で別物扱い
        let sAspect = Double(max(s.width, s.height)) / Double(max(1, min(s.width, s.height)))
        let dAspect = Double(max(d.width, d.height)) / Double(max(1, min(d.width, d.height)))
        guard abs(sAspect - dAspect) < 0.02 else { return .differentPhoto }
        guard (s.dHash ^ d.dHash).nonzeroBitCount <= sameThreshold else { return .differentPhoto }

        let detail = "ソース \(s.label) / 整理先 \(d.label)"
        if Double(s.pixels) > Double(d.pixels) * pixelRatio {
            return .sourceBetter(detail)
        }
        if Double(d.pixels) > Double(s.pixels) * pixelRatio {
            return .sameOrWorse(detail)
        }
        if Double(s.fileSize) > Double(d.fileSize) * sizeRatio {
            return .sourceBetter(detail)
        }
        return .sameOrWorse(detail)
    }
}
