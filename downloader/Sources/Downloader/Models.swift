import Foundation

/// aria2 JSON-RPC の `tellActive`/`tellWaiting`/`tellStopped` が返す1エントリを表す。
/// aria2 はサイズ・速度をすべて文字列(10進バイト数)で返すため、素直に String で受けてから変換する。
struct TorrentItem: Identifiable, Decodable {
    let gid: String
    let status: String            // active / waiting / paused / error / complete / removed
    let totalLength: String
    let completedLength: String
    let uploadLength: String
    let downloadSpeed: String
    let uploadSpeed: String
    let errorMessage: String?
    let bittorrent: Bittorrent?
    let files: [TorrentFile]?
    let followedBy: [String]?

    var id: String { gid }

    /// magnet リンクの追加直後、aria2 はまず「.torrent メタデータ自体のダウンロード」を
    /// 内部的な別 GID として行い(DHT/トラッカー経由でピアを見つけ、ut_metadata 拡張でメタデータを
    /// もらうため数秒かかることがある — 進捗バーが出るまでのラグの正体はこれ)、
    /// 取得が終わると本体データ用の新しい GID に `followedBy` で引き継ぐ。
    /// 引き継ぎ後のメタデータ GID(数十KBで即100%と表示される)は一覧から完全に除外し、
    /// 引き継ぎ前(まだ取得中)のものは「メタデータ取得中」のプレースホルダとして表示する。
    var isMetadataHandoffDone: Bool {
        if let followedBy, !followedBy.isEmpty { return true }
        return false
    }

    var isFetchingMetadata: Bool {
        guard !isMetadataHandoffDone else { return false }
        return files?.first?.path.hasPrefix("[METADATA]") ?? false
    }

    struct Bittorrent: Decodable {
        let info: Info?
        struct Info: Decodable {
            let name: String?
        }
    }

    struct TorrentFile: Decodable {
        let path: String
    }

    var displayName: String {
        if let name = bittorrent?.info?.name, !name.isEmpty { return name }
        if let firstPath = files?.first?.path {
            let name = (firstPath as NSString).lastPathComponent
            return name.hasPrefix("[METADATA]") ? String(name.dropFirst("[METADATA]".count)) : name
        }
        return gid
    }

    /// バイト数だけで完了を判定する(aria2 の `status == "complete"` 遷移を待たない)。
    /// ダウンロード完了後は即座に forceRemove してピアへの UL を止めるために使う。
    var isFullyDownloaded: Bool {
        totalBytes > 0 && completedBytes >= totalBytes
    }

    var totalBytes: Int64 { Int64(totalLength) ?? 0 }
    var completedBytes: Int64 { Int64(completedLength) ?? 0 }
    var uploadedBytes: Int64 { Int64(uploadLength) ?? 0 }
    var downloadSpeedBytes: Int64 { Int64(downloadSpeed) ?? 0 }
    var uploadSpeedBytes: Int64 { Int64(uploadSpeed) ?? 0 }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(completedBytes) / Double(totalBytes)
    }

    var ratio: Double {
        guard completedBytes > 0 else { return 0 }
        return Double(uploadedBytes) / Double(completedBytes)
    }

    var statusLabel: String {
        switch status {
        case "active": return uploadSpeedBytes > downloadSpeedBytes && progress >= 1 ? "シード中" : "ダウンロード中"
        case "waiting": return "待機中"
        case "paused": return "一時停止"
        case "error": return "エラー"
        case "complete": return "完了"
        case "removed": return "削除済み"
        default: return status
        }
    }
}

/// バイト数を読みやすい単位(KB/MB/GB)の文字列にする。
func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

func formatSpeed(_ bytesPerSec: Int64) -> String {
    "\(formatBytes(bytesPerSec))/s"
}
