import Foundation

/// 「ストレージ分析」ペインの内訳1行分(対象フォルダ直下の1フォルダ/ファイル)。
struct StorageBreakdownItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
}

/// 「ストレージ分析」ペインの大きいファイル一覧1件分。
struct LargeFileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    var isSelected: Bool = false
}

/// 指定フォルダ配下を1回の再帰走査で、「直下フォルダ別の内訳」と「大きいファイル一覧」を
/// 同時に集計する。`CacheScanner`(固定パスの既知カテゴリを浅くスキャン)とは違い、任意の
/// フォルダを深く再帰する汎用スキャナ。
enum StorageAnalyzer {
    /// これ未満のファイルは「大きいファイル一覧」には出さない(閾値未満は件数が
    /// 膨大になり一覧の意味が薄れるため)。内訳(直下フォルダ別の合計)には全ファイルを使う。
    static let largeFileThresholdBytes: Int64 = 100 * 1024 * 1024 // 100MB

    struct Result {
        var breakdown: [StorageBreakdownItem] = []
        var largeFiles: [LargeFileItem] = []
        var totalSize: Int64 = 0
    }

    /// OneDrive等のFileProvider拡張が内部管理用に持つ領域。ユーザーに見える
    /// `~/Library/CloudStorage/...`側と同じファイルが(別inodeで)ここにも存在するため、
    /// 除外しないと合計サイズの二重カウント・「大きいファイル」一覧への同一ファイルの
    /// 重複表示が起きる(2026-08-11、OneDriveの動画ファイルで実際に発覚)。アプリの
    /// サンドボックス共有領域でもあり、個別ファイル単位でゴミ箱移動してよい場所でもない。
    private static let excludedAbsolutePaths: [String] = [
        (("~/Library/Group Containers") as NSString).expandingTildeInPath,
    ]

    /// `root`直下の隠しファイル・フォルダ(`.`始まり、`.Trash`含む)、および
    /// `excludedAbsolutePaths`配下は対象外(クリーンペインと役割が重ならないようにする狙いもある)。
    static func scan(root: URL, minLargeFileSize: Int64 = largeFileThresholdBytes) -> Result {
        let fm = FileManager.default
        var bucketSizes: [String: Int64] = [:]
        var bucketOrder: [String] = []
        var largeFiles: [LargeFileItem] = []
        var total: Int64 = 0

        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return Result()
        }

        let rootDepth = root.standardizedFileURL.pathComponents.count

        for case let fileURL as URL in enumerator {
            let components = fileURL.standardizedFileURL.pathComponents
            guard components.count > rootDepth else { continue }
            let topName = components[rootDepth]

            if topName.hasPrefix(".") {
                if components.count == rootDepth + 1 {
                    enumerator.skipDescendants()
                }
                continue
            }

            let standardizedPath = fileURL.standardizedFileURL.path
            if excludedAbsolutePaths.contains(where: { standardizedPath == $0 || standardizedPath.hasPrefix($0 + "/") }) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }

            let allocated = values.totalFileAllocatedSize
            let logical = values.fileSize
            let bytes = Int64(allocated ?? logical ?? 0)

            if bucketSizes[topName] == nil {
                bucketOrder.append(topName)
            }
            bucketSizes[topName, default: 0] += bytes
            total += bytes

            if bytes >= minLargeFileSize {
                largeFiles.append(LargeFileItem(name: fileURL.lastPathComponent, url: fileURL, size: bytes))
            }
        }

        let breakdown = bucketOrder
            .map { name in
                StorageBreakdownItem(name: name, url: root.appendingPathComponent(name), size: bucketSizes[name] ?? 0)
            }
            .sorted { $0.size > $1.size }

        largeFiles.sort { $0.size > $1.size }

        return Result(breakdown: breakdown, largeFiles: largeFiles, totalSize: total)
    }
}
