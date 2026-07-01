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
