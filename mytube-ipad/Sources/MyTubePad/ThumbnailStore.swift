import AVFoundation
import UIKit

/// リモート動画(OneDrive共有リンク)のサムネイルを非同期取得する軽量ストア(2026-08-27追加、
/// 「サムネイルも表示したい」という要望への対応)。mytube(Mac版)の`Core/ThumbnailStore.swift`
/// と同じ「`remoteID`をキャッシュキーにする」方針(tempauth URLは1時間程度で失効しURL自体は
/// キーに使えないため)だが、iPad版は**メモリキャッシュ(`NSCache`)のみ**でディスクキャッシュは
/// 持たない ― MVPとしての単純さを優先した(アプリを再起動すればキャッシュは消えるが、
/// グリッドを開き直せば再取得されるだけなので実用上問題ないと判断)。
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let cache = NSCache<NSString, UIImage>()
    /// 同じ動画への同時呼び出しを1つの`Task`にまとめ、重複生成を避ける
    /// (mytube Mac版の`ThumbnailStore.inFlight`と同じ理由)。
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 200
    }

    func cachedImage(for video: VideoItem) -> UIImage? {
        cache.object(forKey: video.remoteID as NSString)
    }

    func image(for video: VideoItem) async -> UIImage? {
        let key = video.remoteID
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<UIImage?, Never> { [weak self] in
            let asset = AVURLAsset(url: video.downloadURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            do {
                let result = try await generator.image(at: CMTime(seconds: 3, preferredTimescale: 1))
                let image = UIImage(cgImage: result.image)
                self?.cache.setObject(image, forKey: key as NSString)
                return image
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}
