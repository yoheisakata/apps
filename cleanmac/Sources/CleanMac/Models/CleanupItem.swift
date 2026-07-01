import Foundation

/// 削除候補の1項目（キャッシュのサブフォルダなど）。
struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    var isSelected: Bool = true
}

/// キャッシュ掃除のカテゴリ（ユーザーキャッシュ、ログ、ゴミ箱 …）。
struct CacheCategory: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    var items: [CleanupItem]
    var isExpanded: Bool = false

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter { $0.isSelected }.reduce(0) { $0 + $1.size } }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy { $0.isSelected } }
}
