import Foundation

/// ディスク上のサイズ計算などの共通ユーティリティ。
enum FileScanner {
    /// ファイル / ディレクトリの実使用サイズ（バイト）を返す。
    /// アクセスできない要素はスキップして合計に影響させない。
    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            return fileSize(url)
        }

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                   values.isRegularFile == true {
                    total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                }
            }
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    /// ディレクトリ直下の要素を CleanupItem として列挙（サイズ降順）。
    static func childItems(of directory: URL) -> [CleanupItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [CleanupItem] = []
        for url in entries {
            let bytes = size(of: url)
            if bytes > 0 {
                items.append(CleanupItem(name: url.lastPathComponent, url: url, size: bytes))
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}
