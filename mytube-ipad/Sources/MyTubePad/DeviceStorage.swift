import Foundation

/// iPad本体の空き容量/総容量を取得する(2026-08-28追加、「Ipadの全体のストレージ状況も
/// 示してほしい」という要望への対応)。アプリのダウンロードフォルダのサイズ
/// (`DownloadStore.totalDownloadedBytes()`)だけでなく、端末全体でどれだけ空きがあるかも
/// あわせて見せることで、「あとどれくらいダウンロードして大丈夫か」を判断しやすくする。
enum DeviceStorage {
    /// `(端末の総容量, 空き容量)`。ホームディレクトリが乗っているボリューム(=内蔵ストレージ)
    /// の値を`URLResourceValues`から取得する。取得に失敗することは通常無いはずだが、
    /// 念のため`nil`を返せるようにしてある(呼び出し側はこの行を出さないだけでよい)。
    static func totalAndFreeBytes() -> (total: Int64, free: Int64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return nil }
        guard let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return (Int64(total), free)
    }
}
