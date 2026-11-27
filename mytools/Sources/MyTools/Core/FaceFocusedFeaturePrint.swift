import Foundation
import Vision
import ImageIO
import CoreGraphics

/// 「日付推定」ペインの中核。dHash(PerceptualHash)は8x8グレースケールの知覚ハッシュで
/// ほぼ同一カット/バーストショットの検出向き(見た目がわずかでも違うと距離が大きく離れる)なので、
/// 「別の日に撮った、同じ子どもが写っている写真」を探すには向かない。Visionの
/// VNGenerateImageFeaturePrintRequest(オンデバイスの意味的画像特徴量、ネットワーク不要)を使う。
/// さらに顔検出で最大の顔を含む領域だけにクロップしてから特徴量を計算することで、背景や
/// 服装より「写っている人物の見た目」に寄せる(子どもの年齢の手がかりを拾いやすくするため)。
/// 顔が検出できない場合(後ろ姿・風景写真等)は画像全体で計算する。
enum FaceFocusedFeaturePrint {
    /// フル解像度のCGImageをデコードすると(RAW/HEICは1枚あたり数十MB)、大量の候補写真を
    /// concurrentPerformで並列処理する日付推定/参照インデックス構築時にメモリを使い果たす
    /// (実際にこれでメモリ枯渇が発生した)。顔検出・特徴量計算はこの程度の解像度で十分
    /// 機能するため、サムネイルへ縮小してから処理する(PerceptualHash.dHashと同じ方式)。
    private static let maxPixelSize = 640

    static func compute(for url: URL) -> VNFeaturePrintObservation? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return autoreleasepool { () -> VNFeaturePrintObservation? in
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            let target = faceCroppedImage(image) ?? image
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: target, options: [:])
            guard (try? handler.perform([request])) != nil else { return nil }
            return request.results?.first as? VNFeaturePrintObservation
        }
    }

    /// 検出された顔のうち最大のものを、余白60%を付けて画像境界内にクロップする
    /// (髪型・輪郭・上半身の服装まである程度含めることで、特徴量が顔の一部だけに
    /// 過敏に反応しないようにする)。顔が1つも見つからなければnil。
    private static func faceCroppedImage(_ image: CGImage) -> CGImage? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let faces = request.results, !faces.isEmpty else { return nil }
        let largest = faces.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }!

        let w = CGFloat(image.width), h = CGFloat(image.height)
        // VisionのboundingBoxは正規化(0-1)・左下原点。
        var rect = CGRect(x: largest.boundingBox.minX * w,
                           y: largest.boundingBox.minY * h,
                           width: largest.boundingBox.width * w,
                           height: largest.boundingBox.height * h)
        rect = rect.insetBy(dx: -rect.width * 0.6, dy: -rect.height * 0.6)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard rect.width > 1, rect.height > 1 else { return nil }
        return image.cropping(to: rect)
    }
}
