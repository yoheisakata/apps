import Foundation

/// ディスク上のサイズ計算などの共通ユーティリティ。
enum FileScanner {
    /// ファイル / ディレクトリの実使用サイズ（バイト）を返す。
    /// アクセスできない要素はスキップして合計に影響させない。
    static func size(of url: URL) -> Int64 {
        sizeAndCount(of: url).size
    }

    /// ディレクトリ配下のファイル合計サイズと件数を1回の走査でまとめて返す
    /// (サイズだけ・件数だけを個別に`size(of:)`/独自ループで2回走査するより、
    /// 大きいフォルダでは走査コストを半分にできる)。`excludeSyncJunk`をtrueにすると
    /// `.DS_Store`/`._*`(AppleDouble)を集計から除く(既定false、既存呼び出し元の挙動は
    /// 変えない — OneDrive同期ペインが`RsyncSync`の比較対象と揃えるためだけに使う)。
    /// `preferLogicalSize`をtrueにすると`fileSize`(論理サイズ)を`totalFileAllocatedSize`
    /// (ローカル実使用量)より優先する(既定false、既存呼び出し元=キャッシュ掃除等は
    /// 「実際にディスクを解放できる量」を知りたいので現状維持。OneDrive同期ペインだけ
    /// trueで呼ぶ — クラウド専用(未ダウンロード)ファイルは`totalFileAllocatedSize`が
    /// ほぼ0になり、フォルダサイズが実際とかけ離れて小さく出てしまうため。2026-08-11、
    /// conanフォルダで実際に発覚: 329ファイル合計で`totalFileAllocatedSize`はわずか40KBだが
    /// `fileSize`(実際のコンテンツ量)は約101GBだった)。
    static func sizeAndCount(of url: URL, excludeSyncJunk: Bool = false, preferLogicalSize: Bool = false) -> (size: Int64, count: Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, 0) }

        if !isDir.boolValue {
            return (fileSize(url, preferLogicalSize: preferLogicalSize), 1)
        }

        var total: Int64 = 0
        var count = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let fileURL as URL in enumerator {
                if excludeSyncJunk, isSyncJunkFile(fileURL.lastPathComponent) { continue }
                if let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                   values.isRegularFile == true {
                    let allocated = values.totalFileAllocatedSize
                    let logical = values.fileSize
                    let bytes = preferLogicalSize ? (logical ?? allocated ?? 0) : (allocated ?? logical ?? 0)
                    total += Int64(bytes)
                    count += 1
                }
            }
        }
        return (total, count)
    }

    /// `RsyncSync`が同期の比較・転送から除外するジャンクファイル(`.DS_Store`・
    /// AppleDoubleの`._*`)と同じ判定。exFATボリュームはmacOSが拡張属性を保持できない
    /// 代わりに`._<元のファイル名>`というサイドカーファイルを自動生成することがあり、
    /// これを実ファイルとして数えるとrsyncの「同期済み」判定とサイズ/件数表示がズレて
    /// 見える原因になる(2026-08-11、famiconフォルダで実際に発覚: exFAT側だけ`._*`が
    /// 2133件多く、それを除くとソース/ターゲットとも2113件で完全一致した)。
    private static func isSyncJunkFile(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._")
    }

    private static func fileSize(_ url: URL, preferLogicalSize: Bool = false) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        let allocated = values?.totalFileAllocatedSize
        let logical = values?.fileSize
        let bytes = preferLogicalSize ? (logical ?? allocated ?? 0) : (allocated ?? logical ?? 0)
        return Int64(bytes)
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
