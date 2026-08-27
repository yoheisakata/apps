import Foundation

/// 動画のファイルサイズ(ローカル/ダウンロード済みリモート)を取得・キャッシュするストア
/// (2026-08-14追加、「ハイブリッド表示のときは動画のサイズをカラムで表示して」という要望への
/// 対応)。`ThumbnailStore.cachedDuration`/`loadDuration`と同じ設計 ― `VideoTableView`の
/// 「サイズ」列がヘッダークリックでソートする際、`rows`(`videos.map(Row.init)`)は再描画の
/// たびに全動画ぶん作り直されるため、同期的なキャッシュ読み取り(`cachedSize`)を軽量に保つ
/// 必要がある。実際のファイルI/O(`resourceValues`)はメインスレッド外(`Task.detached`)で
/// 行い、結果だけをキャッシュへ書き戻す。
/// **`loadSize`の呼び出し元は表示中の全動画ぶんを一斉に先読みする**(2026-08-21追加、
/// 「サイズのソートがおかしい」というユーザー報告への対応 ― 以前は`VideoTableView`の
/// `SizeCell`が可視セルだけを個別に(セル内に閉じた`@State`で)非同期取得しており、
/// 値が届いても`VideoTableView`自身の`rows`(＝ソート結果)を再計算させる手段が無かった。
/// 画面外でまだ一度もセルが表示されていない動画は`cachedSize`が`nil`のままとなり
/// `fileSizeSortKey`が`.max`扱いになる ― ソートしてもほとんどの行が「サイズ不明」として
/// 束ねられ、ソート自体が効いていないように見えていた。`VideoTableView.loadFileSizes()`
/// (`@State private var fileSizes`)がこのメソッドをまとめて呼び、届いた値で`rows`の
/// 再計算・再ソートを毎回トリガーするように変更した。`limiter`(下記)はこの一斉先読みで
/// 大きいライブラリでも一度に大量のファイルI/Oが走らないようにするための保険。
@MainActor
final class FileSizeStore {
    static let shared = FileSizeStore()

    private let cache = NSCache<NSString, NSNumber>()
    /// `VideoTableView`が「サイズ」列のソートを正しく保つため表示中の全動画ぶんを一斉に
    /// `loadSize(for:)`する(2026-08-21追加、`ThumbnailStore.limiter`と同じ理由 ―
    /// 大きいライブラリで一斉にファイルI/Oが走ってシステムに負荷をかけないよう絞る)。
    private let limiter = ConcurrencyLimiter(limit: 8)

    private init() {}

    /// `video.knownFileSize`(OneDriveのAPIレスポンスに元々含まれるサイズ、`Models.swift`の
    /// ドキュメント参照)があれば、ダウンロード・キャッシュのどちらも介さずそのまま返す ―
    /// ネットワーク/ファイルI/Oが一切不要な最速の経路。
    func cachedSize(for video: VideoItem) -> Int64? {
        video.knownFileSize ?? cache.object(forKey: video.stableKey as NSString)?.int64Value
    }

    /// `knownFileSize`があれば即返す(2026-08-14追加、「前はダウンロードせずにサイズとれた
    /// ような」という指摘への対応 ― OneDriveのAPIレスポンスに元々含まれるサイズを使えば、
    /// ダウンロード前でも正確なサイズが分かる)。無ければダウンロード済みのリモート動画は
    /// `DownloadStore.localFileSize(for:)`(同期、単純なファイルサイズ取得)を使う。
    /// ローカル動画はファイルI/Oを伴うため`Task.detached`でメインスレッド外で
    /// `resourceValues`を呼ぶ。どちらにも当てはまらない(未ダウンロードのYouTube動画等)場合は
    /// サイズを取得する手段が無いため`nil`のまま(表示側は「—」を出す)。
    func loadSize(for video: VideoItem) async -> Int64? {
        if let known = video.knownFileSize { return known }
        if let cached = cachedSize(for: video) { return cached }
        if video.isRemote {
            guard let size = DownloadStore.shared.localFileSize(for: video) else { return nil }
            cache.setObject(NSNumber(value: size), forKey: video.stableKey as NSString)
            return size
        }
        let url = video.url
        await limiter.acquire()
        let size = await Task.detached(priority: .utility) { () -> Int64? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let fileSize = values.fileSize else { return nil }
            return Int64(fileSize)
        }.value
        await limiter.release()
        if let size {
            cache.setObject(NSNumber(value: size), forKey: video.stableKey as NSString)
        }
        return size
    }
}
