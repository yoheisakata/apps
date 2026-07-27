import Foundation

/// Homebrew配下やPATHから外部コマンド(ffmpeg/ffprobe/rsync)の実体を探す。
/// sips/mdlsはmacOS標準で常に/usr/bin配下にあるため対象外。
enum ToolLocator {
    private static var cache: [String: String?] = [:]

    static func resolve(_ name: String) -> String? {
        if let cached = cache[name] { return cached }
        let resolved = locate(name)
        cache[name] = resolved
        return resolved
    }

    static func isAvailable(_ name: String) -> Bool {
        resolve(name) != nil
    }

    static func clearCache() {
        cache.removeAll()
    }

    private static func locate(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [name]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            return nil
        }
        return nil
    }
}
