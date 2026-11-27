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
            // Pipe()を渡して誰も読み取らないと、OSパイプバッファが満杯になった時点でsips側の
            // write()がブロックし待ち合わせでデッドロックし得る(SyncExec.swiftと同じ注意点)上、
            // 大量の写真を処理するとPipeの書き込み端を閉じ忘れてファイルディスクリプタが
            // 積み上がる(H265Encoder用のSyncExec.run/ProcessRunner.runで実際に発生した不具合と
            // 同種)。出力自体は使わないため、そもそも読み取り不要なnullDeviceへ直接捨てる。
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
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
