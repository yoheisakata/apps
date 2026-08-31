import AppKit

/// 写真を`downloadURL`(OneDriveの署名付きURL)から取得し、直近数枚だけメモリにキャッシュする
/// シングルトン。ディスクキャッシュは持たない ― スライドショーは1セッション内で使い切りで、
/// 署名付きURLも1時間程度で失効するため、ディスクに永続化しても再利用価値が薄いと判断した。
@MainActor
final class ImageLoader: ObservableObject {
    static let shared = ImageLoader()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let limit = 8

    private init() {}

    func image(for item: MediaItem) async -> NSImage? {
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

    private nonisolated func fetch(_ url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    private func store(_ image: NSImage, key: String) {
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
