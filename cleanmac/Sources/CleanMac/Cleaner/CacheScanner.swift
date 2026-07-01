import Foundation

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
