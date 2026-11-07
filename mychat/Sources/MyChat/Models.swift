import Foundation

/// 選べるモデル。rawValue は API のモデル ID（会話ファイルに保存されるので変えないこと）。
enum ChatModel: String, CaseIterable, Identifiable, Codable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .opus: return "Opus 5.5"
        case .sonnet: return "Sonnet 5.5"
        case .haiku: return "Haiku 5.5"
        }
    }

    /// サーバー側フォールバック（安全分類器に断られたとき別モデルで続ける）に対応しているか。
    var supportsServerFallback: Bool { self != .haiku }
}

/// 考える深さ（output_config.effort）。
enum Effort: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: return "低（速い）"
        case .medium: return "中"
        case .high: return "高（じっくり）"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    /// アシスタント応答の content ブロック列（JSON 文字列）。thinking ブロックの署名などを含むので、
    /// 次のリクエストでは**手を加えずそのまま**送り返す（履歴を書き換えると thinking ブロックが無効になる）。
    var rawContent: String?
    /// 画面に出す補足（「途中で停止」など）。
    var note: String?
    /// true の発言は API に送らない（拒否されたやりとり）。一度 true にしたら戻さないこと。
    var excluded: Bool = false
    var date = Date()
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = ""
    var model: ChatModel
    /// 会話を作ったときのシステムプロンプト。途中で変えると履歴の書き換えになるので会話ごとに固定。
    var systemPrompt: String
    var messages: [ChatMessage] = []
    var created = Date()
    var updated = Date()

    var displayTitle: String { title.isEmpty ? "新しいチャット" : title }

    /// API に送る messages 配列（追記のみ・過去の発言は一切変えない）。
    func apiMessages() -> [[String: Any]] {
        messages.filter { !$0.excluded }.map { m -> [String: Any] in
            if m.role == .assistant,
               let raw = m.rawContent,
               let arr = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]],
               !arr.isEmpty {
                return ["role": "assistant", "content": arr]
            }
            return ["role": m.role.rawValue, "content": m.text]
        }
    }
}

/// UserDefaults のキー（設定画面と共有）。
enum SettingsKey {
    static let defaultModel = "defaultModel"
    static let effort = "effort"
    static let systemPrompt = "systemPrompt"
    static let defaultSystemPrompt = "あなたは親切で頼りになるアシスタントです。日本語で話しかけられたら日本語で、分かりやすく答えてください。"
}
