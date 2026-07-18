import Foundation

struct Category: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var icon: String
    var isDefault: Bool = false

    static let defaultCategories: [Category] = [
        Category(name: "Web", icon: "globe", isDefault: true),
        Category(name: "メール", icon: "envelope.fill", isDefault: true),
        Category(name: "金融", icon: "yensign.circle.fill", isDefault: true),
        Category(name: "SNS", icon: "person.2.fill", isDefault: true),
        Category(name: "仕事", icon: "briefcase.fill", isDefault: true),
        Category(name: "ショッピング", icon: "cart.fill", isDefault: true),
        Category(name: "その他", icon: "folder.fill", isDefault: true),
    ]

    static let availableIcons = [
        "globe", "envelope.fill", "yensign.circle.fill", "person.2.fill",
        "briefcase.fill", "cart.fill", "folder.fill", "house.fill",
        "gamecontroller.fill", "heart.fill", "star.fill", "book.fill",
        "music.note", "airplane", "car.fill", "cross.case.fill",
        "graduationcap.fill", "wrench.and.screwdriver.fill", "camera.fill",
        "tv.fill", "iphone", "creditcard.fill", "key.fill", "lock.fill",
        "server.rack", "cloud.fill", "wifi", "map.fill",
    ]
}

struct Entry: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var username: String
    var password: String
    var url: String = ""
    var note: String = ""
    var hint: String = ""
    var categoryID: UUID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
}

struct VaultData: Codable {
    var entries: [Entry]
    var categories: [Category]
}
