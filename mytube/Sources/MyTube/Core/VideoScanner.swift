import Foundation

/// 指定フォルダ配下を再帰的に走査し、動画ファイルを `VideoItem` として集める。
enum VideoScanner {
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp",
    ]

    /// ルート直下に直接置かれている動画に付ける「チャンネル」ラベル。
    static let rootChannelLabel = "(ルート)"

    static func scan(root: URL) -> [VideoItem] {
        let start = DispatchTime.now()
        let items = scanImpl(root: root)
        Log.scan.info("scan(\(root.lastPathComponent, privacy: .public)): \(items.count)件 (\(Log.elapsedMs(since: start), format: .fixed(precision: 1))ms)")
        return items
    }

    private static func scanImpl(root: URL) -> [VideoItem] {
        let fm = FileManager.default
        // `.fileSizeKey`は要求しない(2026-08-05、初回ロードのパフォーマンス改善 ―
        // `VideoItem.fileSize`はUI側に表示箇所が無い完全な不使用フィールドだったため削除済み。
        // 要求するキーが減るほど`enumerator`がファイルごとに取得するメタデータも減り、
        // 特にネットワークドライブ/OneDriveの同期フォルダのような1属性ごとのコストが高い
        // ファイルシステムで、大量のファイルを持つフォルダのスキャンが速くなる)。
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // ルートのパスコンポーネントはスキャン全体で不変なので、ファイルごとに
        // 再計算せずループの外で1回だけ計算する(2026-08-05、以前は
        // `folderPathComponents(for:root:)`がファイルごとに`root.standardizedFileURL`を
        // 計算し直しており、大量のファイルを含むフォルダで無駄なオーバーヘッドだった)。
        let rootComponents = root.standardizedFileURL.pathComponents

        var items: [VideoItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if values?.isDirectory == true { continue }
            guard videoExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let folderPath = folderPathComponents(for: url, rootComponents: rootComponents)
            // ルート直下(サブフォルダ無し)の動画は、意味を持たない固定文字列
            // `rootChannelLabel`(「(ルート)」)ではなく、選んだフォルダ自身の名前を
            // チャンネルにする(2026-08-14、「ローカルのローディングでは、チャンネルが
            // ルートになってるけど、フォルダ名をチャンネル名にして」という要望への対応)。
            items.append(VideoItem(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                channel: folderPath.first ?? root.lastPathComponent,
                modifiedDate: values?.contentModificationDate,
                fileExtension: url.pathExtension.lowercased(),
                folderPath: folderPath
            ))
        }
        return items
    }

    /// ルートから見た、動画を含むフォルダのパスコンポーネント(ルート直下なら`[]`)。
    /// 「チャンネル」ラベルは慣例上この先頭要素(無ければ`rootChannelLabel`)を使う。
    private static func folderPathComponents(for url: URL, rootComponents: [String]) -> [String] {
        let fileComponents = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count else { return [] }
        return Array(fileComponents[rootComponents.count...])
    }
}
