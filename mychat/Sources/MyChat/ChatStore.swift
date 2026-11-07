import Foundation
import SwiftUI

/// 会話の一覧・送受信・保存をまとめて持つ。
@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedID: UUID?
    /// 入力欄の下書き（会話ごと）。送信失敗時はここに文章を戻す。
    @Published var drafts: [UUID: String] = [:]

    // 受信中の状態
    @Published private(set) var streamingID: UUID?
    @Published private(set) var streamingText = ""
    @Published private(set) var isThinking = false

    @Published var errorText: String?
    @Published var errorConversationID: UUID?

    private var task: Task<Void, Never>?

    var isStreaming: Bool { streamingID != nil }

    init() {
        load()
        if conversations.isEmpty { newConversation() } else { selectedID = conversations.first?.id }
    }

    // MARK: - 会話の操作

    func conversation(_ id: UUID) -> Conversation? { conversations.first { $0.id == id } }
    private func index(_ id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }

    func newConversation() {
        // 空の会話がすでに先頭にあればそれを使う
        if let first = conversations.first, first.messages.isEmpty {
            selectedID = first.id
            return
        }
        let d = UserDefaults.standard
        let model = ChatModel(rawValue: d.string(forKey: SettingsKey.defaultModel) ?? "") ?? .opus
        let prompt = d.string(forKey: SettingsKey.systemPrompt) ?? SettingsKey.defaultSystemPrompt
        let c = Conversation(model: model, systemPrompt: prompt)
        conversations.insert(c, at: 0)
        selectedID = c.id
        save()
    }

    func delete(_ id: UUID) {
        if streamingID == id { stop() }
        conversations.removeAll { $0.id == id }
        drafts[id] = nil
        if selectedID == id { selectedID = conversations.first?.id }
        if conversations.isEmpty { newConversation() }
        save()
    }

    func setModel(_ model: ChatModel, for id: UUID) {
        guard let i = index(id) else { return }
        conversations[i].model = model
        save()
    }

    // MARK: - 送信

    func send(in id: UUID) {
        let text = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let i = index(id) else { return }
        guard let key = Keychain.load() else {
            errorText = "API キーが設定されていません。メニューの「MyChat」→「設定…」（⌘,）で入力してください。"
            errorConversationID = id
            return
        }
        errorText = nil
        drafts[id] = ""

        let userMsg = ChatMessage(role: .user, text: text)
        conversations[i].messages.append(userMsg)
        if conversations[i].title.isEmpty { conversations[i].title = String(text.prefix(40)) }
        conversations[i].updated = Date()
        // 最近使った会話を先頭へ
        let c = conversations.remove(at: i)
        conversations.insert(c, at: 0)
        save()

        let effort = Effort(rawValue: UserDefaults.standard.string(forKey: SettingsKey.effort) ?? "") ?? .medium
        let payload = c.apiMessages()
        streamingID = c.id
        streamingText = ""
        isThinking = true

        task = Task { [weak self] in
            var text = ""
            var finished = false
            do {
                let stream = ClaudeClient.stream(apiKey: key, model: c.model, effort: effort,
                                                 system: c.systemPrompt, messages: payload)
                for try await event in stream {
                    switch event {
                    case .thinking:
                        self?.isThinking = true
                    case .text(let t):
                        text += t
                        self?.isThinking = false
                        self?.streamingText = text
                    case .done(let raw, let stop):
                        finished = true
                        self?.finish(convID: c.id, userMsgID: userMsg.id, text: text, raw: raw, stopReason: stop)
                    }
                }
                if !finished { self?.finishCancelled(convID: c.id, userMsg: userMsg, text: text) }
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    self?.finishCancelled(convID: c.id, userMsg: userMsg, text: text)
                } else {
                    self?.fail(convID: c.id, userMsg: userMsg, error: error)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
    }

    private func endStreaming() {
        streamingID = nil
        streamingText = ""
        isThinking = false
        task = nil
    }

    private func finish(convID: UUID, userMsgID: UUID, text: String, raw: String?, stopReason: String?) {
        defer { endStreaming(); save() }
        guard let i = index(convID) else { return }
        var reply = ChatMessage(role: .assistant, text: text, rawContent: raw)
        switch stopReason {
        case "refusal":
            // 断られたやりとりは表示だけ残し、以後 API には送らない（途中までの出力も捨てる）
            reply = ChatMessage(role: .assistant, text: "", note: "この内容には回答できないと判断されました。", excluded: true)
            if let u = conversations[i].messages.firstIndex(where: { $0.id == userMsgID }) {
                conversations[i].messages[u].excluded = true
            }
        case "max_tokens":
            reply.note = "長さの上限に達したため、途中で終わっています。"
        default:
            break
        }
        conversations[i].messages.append(reply)
        conversations[i].updated = Date()
    }

    /// 停止ボタンで止めたとき。出力があればそこまでをテキストとして残す（thinking は送り返さない）。
    private func finishCancelled(convID: UUID, userMsg: ChatMessage, text: String) {
        defer { endStreaming(); save() }
        guard let i = index(convID) else { return }
        if text.isEmpty {
            removeUnanswered(userMsg, at: i)
        } else {
            conversations[i].messages.append(ChatMessage(role: .assistant, text: text, note: "途中で停止しました。"))
        }
    }

    /// 通信エラー。送った発言を取り消して入力欄に戻す（送り直せるように）。
    private func fail(convID: UUID, userMsg: ChatMessage, error: Error) {
        defer { endStreaming(); save() }
        errorText = error.localizedDescription
        errorConversationID = convID
        guard let i = index(convID) else { return }
        removeUnanswered(userMsg, at: i)
    }

    private func removeUnanswered(_ userMsg: ChatMessage, at i: Int) {
        // 末尾の（まだ答えのない）発言だけを外す。途中の発言は消さない。
        if conversations[i].messages.last?.id == userMsg.id {
            conversations[i].messages.removeLast()
            if conversations[i].messages.isEmpty { conversations[i].title = "" }
        }
        drafts[conversations[i].id] = userMsg.text
    }

    // MARK: - 保存（~/Library/Application Support/MyChat/conversations.json）

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("conversations.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        conversations = (try? dec.decode([Conversation].self, from: data)) ?? []
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        // 空の会話は保存しない
        let toSave = conversations.filter { !$0.messages.isEmpty }
        if let data = try? enc.encode(toSave) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
