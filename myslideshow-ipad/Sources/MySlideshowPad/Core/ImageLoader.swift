import UIKit

/// 写真を`downloadURL`(OneDriveの署名付きURL)から取得し、直近数枚だけメモリにキャッシュする
/// シングルトン。myslideshow(Mac版)の同名ファイルから移植 ― `NSImage`(AppKit)を
/// `UIImage`(UIKit)に差し替えただけで、ロジックは完全に同じ。ディスクキャッシュは持たない
/// 理由もMac版と同じ(1セッション使い切り、署名付きURLも1時間程度で失効するため)。
@MainActor
final class ImageLoader: ObservableObject {
    static let shared = ImageLoader()

    private var cache: [String: UIImage] = [:]
    private var order: [String] = []
    private let limit = 8

    private init() {}

    func image(for item: MediaItem) async -> UIImage? {
        if let cached = cache[item.remoteID] { return cached }
        guard let image = await fetch(item.downloadURL) else { return nil }
        store(image, key: item.remoteID)
        return image
    }

    /// 次に表示されそうな写真を先読みしておく(表示が切り替わった瞬間の空白を減らすため)。
    func prefetch(_ items: [MediaItem]) {
        for item in items where item.kind == .photo && cache[item.remoteID] == nil {
            Task {
                guard let image = await fetch(item.downloadURL) else { return }
                store(image, key: item.remoteID)
            }
        }
    }

    private nonisolated func fetch(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    private func store(_ image: UIImage, key: String) {
        if cache[key] == nil {
            order.append(key)
        }
        cache[key] = image
        while order.count > limit {
            let oldest = order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
