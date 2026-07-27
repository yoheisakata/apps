import Foundation
import SwiftUI

@MainActor
final class CacheViewModel: ObservableObject {
    @Published var categories: [CacheCategory] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var hasScanned = false
    @Published var status = ""
    /// 削除に失敗した項目があるときのエラーダイアログ用メッセージ。
    @Published var errorMessage: String?

    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var hasSelection: Bool { selectedSize > 0 }

    func scan() async {
        isScanning = true
        status = ""
        let result = await Task.detached(priority: .userInitiated) {
            CacheScanner.scanAll()
        }.value
        categories = result
        hasScanned = true
        isScanning = false
        if result.isEmpty {
            status = "削除できるキャッシュは見つかりませんでした。"
        }
    }

    func clean() async {
        isCleaning = true
        let urls = categories.flatMap { category in
            category.items.filter { $0.isSelected }.map { $0.url }
        }
        var result = await Task.detached(priority: .userInitiated) {
            FileRemover.moveToTrash(urls)
        }.value
        // 権限エラーなどで失敗した分は Finder 経由で再試行する
        if !result.failures.isEmpty {
            result = FileRemover.retryWithFinder(result)
        }
        await scan()
        isCleaning = false

        var message = "\(result.trashed.count) 項目をゴミ箱に移動しました。"
        if !result.failures.isEmpty {
            message += " \(result.failures.count) 項目は権限などの理由で移動できませんでした。"
        }
        status = message

        if var detail = result.failureMessage() {
            detail += "\n\n使用中のファイルや、フルディスクアクセスの許可が必要な場所は移動できないことがあります。"
            errorMessage = detail
        }
    }

    func setAllSelected(in categoryID: UUID, to value: Bool) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        for itemIndex in categories[index].items.indices {
            categories[index].items[itemIndex].isSelected = value
        }
    }
}
