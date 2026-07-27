import Foundation

enum HEICConverter {
    /// HEIC → JPG(品質90%) に変換し、一時ファイルのURLを返す。呼び出し元が後片付けすること。
    static func convertToJPG(_ source: URL) -> URL? {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tmpFile = tmpDir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".jpg")

        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = [
                "-s", "format", "jpeg",
                "-s", "formatOptions", "90",
                source.path, "--out", tmpFile.path,
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: tmpFile.path) else {
                try? FileManager.default.removeItem(at: tmpDir)
                return nil
            }
            return tmpFile
        } catch {
            try? FileManager.default.removeItem(at: tmpDir)
            return nil
        }
    }

    static func cleanup(_ tmpFile: URL) {
        try? FileManager.default.removeItem(at: tmpFile.deletingLastPathComponent())
    }
}
