import Foundation

/// 削除はすべて「ゴミ箱へ移動」。完全削除は行わない（復元可能）。
enum FileRemover {
    struct Failure: Identifiable {
        let id = UUID()
        let url: URL
        let message: String
    }

    struct Result {
        var trashed: [URL] = []
        var failures: [Failure] = []
    }

    static func moveToTrash(_ urls: [URL]) -> Result {
        var result = Result()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.trashed.append(url)
            } catch {
                result.failures.append(Failure(url: url, message: error.localizedDescription))
            }
        }
        return result
    }
}

extension FileRemover.Result {
    /// 失敗した項目をユーザー向けのエラーメッセージに整形する（失敗がなければ nil）。
    /// `highlight` に含まれる URL は「アプリ本体」、それ以外は「関連ファイル」と表示する。
    func failureMessage(appURLs highlight: Set<URL> = []) -> String? {
        guard !failures.isEmpty else { return nil }
        var lines: [String] = []
        for failure in failures.prefix(8) {
            if highlight.isEmpty {
                lines.append("・\(failure.url.lastPathComponent)\n　→ \(failure.message)")
            } else {
                let kind = highlight.contains(failure.url) ? "アプリ本体" : "関連ファイル"
                lines.append("・\(failure.url.lastPathComponent)（\(kind)）\n　→ \(failure.message)")
            }
        }
        var text = lines.joined(separator: "\n")
        if failures.count > 8 {
            text += "\nほか \(failures.count - 8) 件"
        }
        return text
    }
}
