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

/// ユーザー領域のキャッシュ・ログ・ゴミ箱などをスキャンする。
/// システム領域(/System, /private/var 等)は権限や安全性の観点から対象外。
enum CacheScanner {
    static func scanAll() -> [CacheCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let definitions: [(String, String, String, String)] = [
            ("ユーザーキャッシュ", "~/Library/Caches", "internaldrive", "Library/Caches"),
            ("アプリのログ", "~/Library/Logs", "doc.text", "Library/Logs"),
            ("ゴミ箱", "~/.Trash", "trash", ".Trash"),
            ("Xcode DerivedData", "~/Library/Developer/Xcode/DerivedData", "hammer",
             "Library/Developer/Xcode/DerivedData"),
            ("Xcode iOS DeviceSupport", "~/Library/Developer/Xcode/iOS DeviceSupport", "iphone",
             "Library/Developer/Xcode/iOS DeviceSupport"),
            ("Xcode アーカイブ", "~/Library/Developer/Xcode/Archives", "archivebox",
             "Library/Developer/Xcode/Archives"),
            ("iOSデバイスのバックアップ", "~/Library/Application Support/MobileSync/Backup", "iphone.gen3",
             "Library/Application Support/MobileSync/Backup"),
            ("Xcodeシミュレータ", "~/Library/Developer/CoreSimulator/Devices", "apps.iphone",
             "Library/Developer/CoreSimulator/Devices"),
        ]

        var categories: [CacheCategory] = []
        for (title, subtitle, image, relativePath) in definitions {
            let dir = home.appending(path: relativePath)
            let items = FileScanner.childItems(of: dir)
            if !items.isEmpty {
                categories.append(CacheCategory(
                    title: title,
                    subtitle: subtitle,
                    systemImage: image,
                    items: items
                ))
            }
        }

        return categories
    }
}
