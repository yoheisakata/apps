import Foundation

enum SyncExecError: Error, LocalizedError {
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let executable): return "\(executable) がタイムアウトしました"
        }
    }
}

/// 短時間で終わるコマンド（ffprobe/sips/mdls等でのメタデータ取得）を同期実行して標準出力を返す共通ヘルパー。
/// 長時間かかるコマンド(ffmpeg本体等)はProcessRunnerを使うこと。
enum SyncExec {
    /// stdoutは読み取りハンドラで都度ドレインする(waitUntilExitを先に呼ぶとOSパイプバッファが
    /// 満杯になった時点で子プロセス側のwrite()がブロックし、待ち合わせでデッドロックし得るため)。
    /// stderrは破棄(nullDevice)。timeout経過後も終了しないプロセスはterminateしてエラーにする
    /// (壊れたファイルやネットワークドライブの応答停止でスキャン全体が無限に止まるのを防ぐ)。
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 20) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var outputData = Data()
        let dataQueue = DispatchQueue(label: "SyncExec.output")
        pipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            dataQueue.sync { outputData.append(chunk) }
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            // readabilityHandlerを設定済みのままpipeを放置するとファイルディスクリプタが
            // 解放されない(ProcessRunner.runと同じ理由)。起動失敗のたびにリークし、
            // 積み重なると後続の起動が未捕捉例外でクラッシュし得るため明示的に閉じる。
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            throw error
        }
        // 子プロセスに複製された後、親側が持つ書き込み端の複製は不要になる。ここで閉じずに
        // 放置すると、この関数を数千回呼ぶ処理(エンコード対象フォルダの一括ffprobeスキャン等)で
        // ファイルディスクリプタが線形に積み上がり、OSの上限に達した時点で以降すべての呼び出しが
        // 「出力が読めない」で失敗し続ける不具合になる(実際にファイル1500件超のフォルダで発生した)。
        try? pipe.fileHandleForWriting.close()

        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForReading.close()

        if timedOut {
            process.terminationHandler = nil
            process.terminate()
            throw SyncExecError.timedOut(executable)
        }

        return dataQueue.sync { String(data: outputData, encoding: .utf8) ?? "" }
    }
}
