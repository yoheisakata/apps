import Foundation

/// Homebrew で導入された yt-dlp / ffmpeg の場所を解決する。
/// GUI アプリは Finder から起動すると最小限の PATH しか持たないため、
/// まず既知の Homebrew パスを直接調べ、見つからなければログインシェルの which に頼る。
enum ToolLocator {
    /// Apple Silicon と Intel 両方の Homebrew prefix を含む候補パス。
    private static let searchDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    static func locate(_ name: String) -> String? {
        for dir in searchDirs {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return loginShellWhich(name)
    }

    /// `zsh -lc 'which <name>'` でログインシェルの PATH を使って解決する。
    private static func loginShellWhich(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
