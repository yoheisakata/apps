import UIKit

/// 写真を取得し、直近数十枚だけメモリにキャッシュするシングルトン。myslideshow-ipadの
/// 同名ファイル(`NSImage`→`UIImage`化されたもの)がベースだが、**2つの独立した用途に
/// 分けた(このアプリ独自の変更)**:
///
/// - `thumbnail(for:)` — グリッドのサムネイル用。`MediaItem.thumbnailURL`
///   (mygallery Mac版が2026-09-07に追加した、OneDriveサーバー側生成済みの数百px
///   サムネイル)があればそちらを使い、無ければ`downloadURL`(元ファイル)に
///   フォールバックする。myslideshow-ipadの`MediaItem`にはこのフィールドが無かった
///   ため、この分岐自体がこのアプリで新規に必要になったもの。
/// - `image(for:)` — ビューア/スライドショーのフルサイズ表示用。常に`downloadURL`
///   (元ファイル)を使う ― サムネイルは数百pxしかなく実際に見るときの画質には
///   全く足りないため(mygallery Mac版の`ThumbnailLoader`と同じ判断)。
///
/// 用途ごとにキャッシュキーを分けている(同じ`remoteID`でもサムネイルとフルサイズは
/// 別物のため)。キャッシュ上限もスライドショー専用だったmyslideshow-ipadの8枚から、
/// グリッド全体を素早くスクロールできるよう60枚に増やした。ディスクキャッシュは
/// 持たない(1セッション使い切り、署名付きURLも1時間程度で失効するため) ―
/// これはmyslideshow-ipad/mygallery(Mac版)双方と同じ判断。
@MainActor
final class ImageLoader: ObservableObject {
    static let shared = ImageLoader()

    private var cache: [String: UIImage] = [:]
    private var order: [String] = []
    private let limit = 60

    private init() {}

    func thumbnail(for item: MediaItem) async -> UIImage? {
        let key = "thumb:\(item.remoteID)"
        if let cached = cache[key] { return cached }
        guard let image = await fetch(item.thumbnailURL ?? item.downloadURL) else { return nil }
        store(image, key: key)
        return image
    }

    func image(for item: MediaItem) async -> UIImage? {
        let key = "full:\(item.remoteID)"
        if let cached = cache[key] { return cached }
        guard let image = await fetch(item.downloadURL) else { return nil }
        store(image, key: key)
        return image
    }

    /// 次に表示されそうな写真のフルサイズ画像を先読みしておく(ビューア/スライドショーの
    /// 表示切り替え時の空白を減らすため)。
    func prefetch(_ items: [MediaItem]) {
        for item in items where item.kind == .photo && cache["full:\(item.remoteID)"] == nil {
            Task {
                guard let image = await fetch(item.downloadURL) else { return }
                store(image, key: "full:\(item.remoteID)")
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
