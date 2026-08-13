import Foundation

/// お気に入りと起動回数の永続化(UserDefaults)。キーは ScannedROM.id。
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: Set<String>
    @Published private(set) var launchCounts: [String: Int]

    private let favoritesKey = "favoriteROMs"
    private let countsKey = "launchCounts"

    private init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        launchCounts = (UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    func addFavorite(_ id: String) {
        favorites.insert(id)
        save()
    }

    func removeFavorite(_ id: String) {
        favorites.remove(id)
        save()
    }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        save()
    }

    func recordLaunch(_ id: String) {
        launchCounts[id, default: 0] += 1
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
        UserDefaults.standard.set(launchCounts, forKey: countsKey)
    }
}
