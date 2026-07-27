import Foundation

/// UserDefaults に保存する設定のキーと初期値。SettingsView(@AppStorage)と Aria2Engine の両方から
/// 同じキーを参照することで、設定変更が即座にエンジンへ反映できるようにする。
enum Settings {
    static let downloadDirKey = "downloadDir"
    static let maxUploadKBpsKey = "maxUploadKBps"       // 0 = 無制限
    static let maxDownloadKBpsKey = "maxDownloadKBps"   // 0 = 無制限
    static let seedRatioKey = "seedRatio"               // 0 = 完了後すぐシード停止
    static let seedTimeMinutesKey = "seedTimeMinutes"   // 0 = 完了後すぐシード停止

    static var defaultDownloadDir: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Torrents").path
            ?? NSHomeDirectory() + "/Downloads/Torrents"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            downloadDirKey: defaultDownloadDir,
            maxUploadKBpsKey: 50,
            maxDownloadKBpsKey: 0,
            seedRatioKey: 0,
            seedTimeMinutesKey: 0,
        ])
    }
}

/// aria2c を子プロセスとして起動し、JSON-RPC 経由で torrent の追加・進捗取得・一時停止/削除を行う。
/// アップロード/ダウンロード速度上限は `aria2.changeGlobalOption` でホットリロードできるが、
/// seed-ratio / seed-time は起動時オプションのため、変更には `restart()` が必要。
@MainActor
final class Aria2Engine: ObservableObject {
    @Published var torrents: [TorrentItem] = []
    @Published var isReady = false
    @Published var lastError: String?

    let aria2Path = ToolLocator.locate("aria2c")
    var toolsReady: Bool { aria2Path != nil }

    private var process: Process?
    private var pollTask: Task<Void, Never>?
    private let port = Int.random(in: 16800...16900)
    private let secret = UUID().uuidString

    private var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Downloader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var sessionFile: URL { supportDir.appendingPathComponent("session.aria2") }
    private var logFile: URL { supportDir.appendingPathComponent("aria2.log") }
    private var appLogFile: URL { supportDir.appendingPathComponent("app.log") }

    /// AppDelegate など外部から「イベントは受信できたか」を記録するための公開口。
    func noteEvent(_ message: String) {
        appendLog(message)
    }

    /// magnet: リンクの受信・追加の成否をファイルに残す。aria2c 自体のログ(`--log-level=warn`)には
    /// RPC 呼び出しの成否が出ないため、ブラウザ起動まわりの不具合調査はここを見るのが早い。
    private func appendLog(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: appLogFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: appLogFile)
        }
    }

    private var rpcURL: URL { URL(string: "http://127.0.0.1:\(port)/jsonrpc")! }

    // MARK: - ライフサイクル

    func start() {
        guard let aria2 = aria2Path, process == nil else { return }

        let downloadDir = UserDefaults.standard.string(forKey: Settings.downloadDirKey) ?? Settings.defaultDownloadDir
        try? FileManager.default.createDirectory(atPath: downloadDir, withIntermediateDirectories: true)

        let uploadKBps = UserDefaults.standard.integer(forKey: Settings.maxUploadKBpsKey)
        let downloadKBps = UserDefaults.standard.integer(forKey: Settings.maxDownloadKBpsKey)
        let seedRatio = UserDefaults.standard.integer(forKey: Settings.seedRatioKey)
        let seedTimeMinutes = UserDefaults.standard.integer(forKey: Settings.seedTimeMinutesKey)

        var args = [
            "--enable-rpc",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(secret)",
            "--rpc-listen-all=false",
            "--dir=\(downloadDir)",
            "--continue=true",
            "--file-allocation=none",
            "--max-overall-upload-limit=\(uploadKBps)K",
            "--max-overall-download-limit=\(downloadKBps)K",
            "--seed-ratio=\(seedRatio)",
            "--seed-time=\(seedTimeMinutes)",
            "--save-session=\(sessionFile.path)",
            "--save-session-interval=30",
            "--log=\(logFile.path)",
            "--log-level=warn",
        ]
        if FileManager.default.fileExists(atPath: sessionFile.path) {
            args.append("--input-file=\(sessionFile.path)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: aria2)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            process = proc
        } catch {
            lastError = "aria2c の起動に失敗しました: \(error.localizedDescription)"
            return
        }

        startPolling()
    }

    /// seed-ratio / seed-time など起動時オプションを変更した後に呼ぶ。
    func restart() {
        stop()
        start()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let proc = process, proc.isRunning {
            Task { try? await call("aria2.shutdown", params: []) }
            proc.terminate()
        }
        process = nil
        isReady = false
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// 完了直後に forceRemove を投げた GID。同じ GID に何度も remove RPC を送らないための重複防止。
    private var removalRequested: Set<String> = []

    private func refresh() async {
        do {
            let active: [TorrentItem] = try await callList("aria2.tellActive", params: [])
            let waiting: [TorrentItem] = try await callList("aria2.tellWaiting", params: [0, 100])
            let stopped: [TorrentItem] = try await callList("aria2.tellStopped", params: [0, 100])
            let fetched = active + waiting + stopped

            // ダウンロード完了を検知したら即座に forceRemove して一覧からも消す。
            // status が "complete" になる(= aria2 が seed-ratio/seed-time の判定を終える)のを
            // 待たず、バイト数だけで 100% と分かった時点で自分から切断しにいく — これにより
            // seed-ratio=0 の判定が回るまでのわずかな間もピアへの UL を発生させない。
            let doneGIDs = Set(fetched.filter { $0.status == "complete" || $0.isFullyDownloaded }.map(\.gid))
            for gid in doneGIDs where !removalRequested.contains(gid) {
                removalRequested.insert(gid)
                remove(gid)
            }

            // 引き継ぎ済みのメタデータ GID(数十KBで即100%になる)は一覧から除く。
            // 引き継ぎ前(取得中)のものは isFetchingMetadata としてプレースホルダ表示に回す。
            torrents = fetched.filter { !$0.isMetadataHandoffDone && !doneGIDs.contains($0.gid) }
            isReady = true
            // 注意: ここで lastError を nil に戻さない。一覧取得(このメソッド)と追加操作
            // (addMagnet/addTorrentFile)は別々に失敗しうるため、1秒ごとに走るこのポーリングが
            // 直前の「追加に失敗しました」バナーを毎回消してしまい、ユーザーに何も見せないまま
            // 失敗が握りつぶされるバグがあった。追加系のエラーは次の追加操作が始まった時にだけ消す。
        } catch {
            // 起動直後は RPC がまだ listen していないことがあるので静かに次回リトライする。
            isReady = false
        }
    }

    // MARK: - 追加

    func addMagnet(_ uri: String) {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendLog("addMagnet 受信: \(trimmed.prefix(100))")
        Task {
            await addWithRetry { try await self.call("aria2.addUri", params: [[trimmed]]) }
        }
    }

    func addTorrentFile(at url: URL) {
        appendLog("addTorrentFile 受信: \(url.lastPathComponent)")
        Task {
            await addWithRetry {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()
                return try await self.call("aria2.addTorrent", params: [base64])
            }
        }
    }

    /// magnet: リンクによる起動直後は aria2c がまだ RPC を listen していないことがあるため、
    /// 少し待ってからリトライする(ブラウザでのクリック起動を確実に成功させるため)。
    private func addWithRetry(_ operation: @escaping () async throws -> Any) async {
        lastError = nil
        for attempt in 0..<10 {
            do {
                let result = try await operation()
                appendLog("追加成功: \(result)")
                return
            } catch {
                if attempt == 9 {
                    let message = "追加に失敗しました: \(error.localizedDescription)"
                    lastError = message
                    appendLog("追加失敗(最終, \(attempt + 1)回目): \(error)")
                } else {
                    appendLog("追加リトライ待ち(\(attempt + 1)回目): \(error)")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
    }

    // MARK: - 操作

    func pause(_ gid: String) {
        Task { try? await call("aria2.pause", params: [gid]) }
    }

    func unpause(_ gid: String) {
        Task { try? await call("aria2.unpause", params: [gid]) }
    }

    func remove(_ gid: String) {
        Task {
            _ = try? await call("aria2.forceRemove", params: [gid])
            _ = try? await call("aria2.removeDownloadResult", params: [gid])
        }
    }

    /// アップロード/ダウンロード速度上限はプロセス再起動なしで即時反映できる。
    func applySpeedLimits() {
        let uploadKBps = UserDefaults.standard.integer(forKey: Settings.maxUploadKBpsKey)
        let downloadKBps = UserDefaults.standard.integer(forKey: Settings.maxDownloadKBpsKey)
        Task {
            try? await call("aria2.changeGlobalOption", params: [
                [
                    "max-overall-upload-limit": "\(uploadKBps)K",
                    "max-overall-download-limit": "\(downloadKBps)K",
                ]
            ])
        }
    }

    // MARK: - JSON-RPC

    private func callList(_ method: String, params: [Any]) async throws -> [TorrentItem] {
        let data = try await rpcResultData(method, params: params)
        return try JSONDecoder().decode([TorrentItem].self, from: data)
    }

    @discardableResult
    private func call(_ method: String, params: [Any]) async throws -> Any {
        let data = try await rpcResultData(method, params: params)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func rpcResultData(_ method: String, params: [Any]) async throws -> Data {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": ["token:\(secret)"] + params,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let errorObj = json?["error"] as? [String: Any] {
            let message = errorObj["message"] as? String ?? "unknown RPC error"
            throw NSError(domain: "Aria2RPC", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard let result = json?["result"] else {
            throw NSError(domain: "Aria2RPC", code: 2, userInfo: [NSLocalizedDescriptionKey: "no result"])
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
    }
}
