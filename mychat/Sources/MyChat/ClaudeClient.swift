import Foundation

enum ClaudeError: LocalizedError {
    case http(Int, String)
    case api(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg):
            switch code {
            case 401: return "API キーが正しくないようです（401）。設定を確認してください。\n\(msg)"
            case 429: return "利用制限に達しました（429）。少し待ってから送り直してください。\n\(msg)"
            case 529: return "サーバーが混み合っています（529）。少し待ってから送り直してください。"
            default: return "エラー（\(code)）: \(msg)"
            }
        case .api(let msg): return "エラー: \(msg)"
        case .badResponse: return "サーバーの応答を読めませんでした。"
        }
    }
}

enum StreamEvent {
    /// 考え中（thinking ブロック開始）
    case thinking
    /// 応答テキストの断片
    case text(String)
    /// 完了。raw = 送り返す用の content ブロック列(JSON)、stopReason = stop_reason
    case done(raw: String?, stopReason: String?)
}

/// Messages API を URLSession で直接呼ぶ（Swift には公式 SDK がないため raw HTTP + SSE）。
enum ClaudeClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    static func stream(apiKey: String, model: ChatModel, effort: Effort,
                       system: String, messages: [[String: Any]]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(apiKey: apiKey, model: model, effort: effort,
                                  system: system, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(apiKey: String, model: ChatModel, effort: Effort, system: String,
                            messages: [[String: Any]],
                            continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 64000,
            "stream": true,
            "messages": messages,
            "output_config": ["effort": effort.rawValue],
        ]
        let sys = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty { body["system"] = sys }
        if model.supportsServerFallback {
            // 安全分類器に断られたとき、サーバー側で自動的に別モデルで続けてもらう
            body["fallbacks"] = "default"
            req.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        if http.statusCode != 200 {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw ClaudeError.http(http.statusCode, errorMessage(from: data))
        }

        // content ブロックを組み立てる。SSE の index → blocks 配列の位置。
        var blocks: [[String: Any]] = []
        var position: [Int: Int] = [:]
        var stopReason: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                guard let index = obj["index"] as? Int,
                      let block = obj["content_block"] as? [String: Any] else { break }
                position[index] = blocks.count
                blocks.append(block)
                if (block["type"] as? String) == "thinking" { continuation.yield(.thinking) }

            case "content_block_delta":
                guard let index = obj["index"] as? Int, let p = position[index],
                      let delta = obj["delta"] as? [String: Any],
                      let dtype = delta["type"] as? String else { break }
                switch dtype {
                case "text_delta":
                    let t = delta["text"] as? String ?? ""
                    blocks[p]["text"] = (blocks[p]["text"] as? String ?? "") + t
                    continuation.yield(.text(t))
                case "thinking_delta":
                    let t = delta["thinking"] as? String ?? ""
                    blocks[p]["thinking"] = (blocks[p]["thinking"] as? String ?? "") + t
                case "signature_delta":
                    blocks[p]["signature"] = (blocks[p]["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
                default:
                    break
                }

            case "message_delta":
                if let d = obj["delta"] as? [String: Any], let s = d["stop_reason"] as? String { stopReason = s }

            case "error":
                let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "不明なエラー"
                throw ClaudeError.api(msg)

            default:
                break
            }
        }

        let echo = echoBlocks(blocks)
        var raw: String?
        if !echo.isEmpty, let data = try? JSONSerialization.data(withJSONObject: echo) {
            raw = String(data: data, encoding: .utf8)
        }
        continuation.yield(.done(raw: raw, stopReason: stopReason))
    }

    /// 次のリクエストで送り返すブロック。途中でフォールバックが起きた場合は、最後の fallback ブロックより前は
    /// text だけ残す（thinking などは別モデルのものなので送らない）。fallback ブロック自体は監査用の印なので外す。
    static func echoBlocks(_ blocks: [[String: Any]]) -> [[String: Any]] {
        let types = blocks.map { $0["type"] as? String ?? "" }
        guard let last = types.lastIndex(of: "fallback") else { return blocks }
        var out: [[String: Any]] = []
        for (i, b) in blocks.enumerated() {
            if i < last { if types[i] == "text" { out.append(b) } }
            else if i > last { out.append(b) }
        }
        return out
    }

    static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
