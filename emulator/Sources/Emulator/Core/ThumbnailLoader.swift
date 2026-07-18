import SwiftUI
import CryptoKit

final class ThumbnailLoader: ObservableObject {
    static let shared = ThumbnailLoader()

    private let cacheDir: URL
    private let session: URLSession
    private var inFlight: Set<String> = []

    @Published var images: [String: NSImage] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("RetroGames/Thumbnails")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    func loadThumbnail(for game: GameTitle) {
        if images[game.id] != nil { return }

        if let cached = loadFromCache(game) {
            DispatchQueue.main.async {
                self.images[game.id] = cached
            }
            return
        }

        guard !inFlight.contains(game.id) else { return }
        inFlight.insert(game.id)

        let urlString = thumbnailURL(for: game)
        guard let url = URL(string: urlString) else {
            inFlight.remove(game.id)
            return
        }

        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            defer {
                DispatchQueue.main.async { self.inFlight.remove(game.id) }
            }

            guard let data, let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data) else { return }

            self.saveToCache(game, data: data)

            DispatchQueue.main.async {
                self.images[game.id] = image
            }
        }
        task.resume()
    }

    private func thumbnailURL(for game: GameTitle) -> String {
        let system = game.system.thumbnailSystem
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? game.system.thumbnailSystem
        let name = game.thumbnailName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? game.thumbnailName
        return "https://thumbnails.libretro.com/\(system)/Named_Boxarts/\(name).png"
    }

    private func cacheFile(for game: GameTitle) -> URL {
        let safe = game.id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDir.appendingPathComponent("\(safe).png")
    }

    private func loadFromCache(_ game: GameTitle) -> NSImage? {
        let file = cacheFile(for: game)
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private func saveToCache(_ game: GameTitle, data: Data) {
        let file = cacheFile(for: game)
        try? data.write(to: file)
    }
}
