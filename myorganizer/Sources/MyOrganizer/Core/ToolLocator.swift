import Foundation

/// Homebrew配下やPATHから外部コマンド(ffmpeg/ffprobe/rsync)の実体を探す。
/// sips/mdlsはmacOS標準で常に/usr/bin配下にあるため対象外。
enum ToolLocator {
    private static var cache: [String: String?] = [:]
    /// キャッシュ辞書への同時アクセスから守るロック。以前は排他制御なしだったため、
    /// 複数スレッドから同時に初回`resolve`が呼ばれる(=同じキーへ同時書き込みが起きる)と
    /// Dictionaryの内部バッファが壊れてクラッシュし得た(`VideoDupFinder`が
    /// `DispatchQueue.concurrentPerform`で`resolve("ffmpeg")`/`resolve("ffprobe")`を
    /// 並列に呼ぶようになって初めて顕在化した)。
    private static let lock = NSLock()

    static func resolve(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        let resolved = locate(name)
        cache[name] = resolved
        return resolved
    }

    static func isAvailable(_ name: String) -> Bool {
        resolve(name) != nil
    }

    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
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
