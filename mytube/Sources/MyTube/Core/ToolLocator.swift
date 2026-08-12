import Foundation

/// Homebrewで導入されたyt-dlp/ffmpegの場所を解決する(`downloader/Sources/Downloader/ToolLocator.swift`
/// と同じ実装)。GUIアプリはFinderから起動すると最小限のPATHしか持たないため、まず既知の
/// Homebrewパスを直接調べ、見つからなければログインシェルのwhichに頼る。
enum ToolLocator {
    /// Apple SiliconとIntel両方のHomebrew prefixを含む候補パス。
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

    /// `zsh -lc 'which <name>'` でログインシェルのPATHを使って解決する。
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
