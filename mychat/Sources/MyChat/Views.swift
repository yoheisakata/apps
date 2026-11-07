import AppKit
import SwiftUI

// MARK: - 全体

struct ContentView: View {
    @EnvironmentObject var store: ChatStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedID) {
                ForEach(store.conversations) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.displayTitle).lineLimit(1)
                        Text(c.updated.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(c.id)
                    .contextMenu {
                        Button("削除", role: .destructive) { store.delete(c.id) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 230)
            .toolbar {
                ToolbarItem {
                    Button { store.newConversation() } label: {
                        Label("新しいチャット", systemImage: "square.and.pencil")
                    }
                    .help("新しいチャット（⌘N）")
                }
            }
        } detail: {
            if let id = store.selectedID, store.conversation(id) != nil {
                ChatView(conversationID: id).id(id)
            } else {
                Text("左の一覧からチャットを選ぶか、⌘N で新しく始めてください。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 1つの会話

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    let conversationID: UUID
    @FocusState private var inputFocused: Bool

    private var conv: Conversation? { store.conversation(conversationID) }
    private var streamingHere: Bool { store.streamingID == conversationID }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if conv?.messages.isEmpty ?? true, !streamingHere {
                            EmptyChatHint()
                        }
                        ForEach(conv?.messages ?? []) { m in
                            MessageRow(message: m).id(m.id)
                        }
                        if streamingHere {
                            StreamingRow(text: store.streamingText, thinking: store.isThinking)
                        }
                        if let err = store.errorText, store.errorConversationID == conversationID {
                            ErrorBox(text: err) { store.errorText = nil }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(20)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: store.streamingText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: conv?.messages.count ?? 0) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            inputBar
        }
        .navigationTitle(conv?.displayTitle ?? "MyChat")
        .toolbar {
            ToolbarItem {
                Picker("モデル", selection: Binding(
                    get: { conv?.model ?? .opus },
                    set: { store.setModel($0, for: conversationID) }
                )) {
                    ForEach(ChatModel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(streamingHere)
                .help("この会話で使うモデル")
            }
        }
        .onAppear { inputFocused = true }
    }

    private var draft: Binding<String> {
        Binding(get: { store.drafts[conversationID] ?? "" },
                set: { store.drafts[conversationID] = $0 })
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("メッセージを入力（Return で送信、⌥Return で改行）", text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...10)
                .focused($inputFocused)
                .onSubmit { store.send(in: conversationID) }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
            if streamingHere {
                Button { store.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .help("止める")
            } else {
                Button { store.send(in: conversationID) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(store.isStreaming || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("送信")
            }
        }
        .padding(12)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
    }
}

struct EmptyChatHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Claude に話しかけてみましょう").font(.title3)
            Text("モデルは右上で切り替えられます。API キーや考える深さは「設定…」（⌘,）から。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - 発言

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.18)))
                    .opacity(message.excluded ? 0.5 : 1)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty {
                    MarkdownText(text: message.text)
                }
                HStack(spacing: 10) {
                    if let note = message.note {
                        Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if !message.text.isEmpty {
                        CopyButton(text: message.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StreamingRow: View {
    let text: String
    let thinking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !text.isEmpty { MarkdownText(text: text) }
            if thinking || text.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("考え中…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorBox: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Label(copied ? "コピーしました" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

// MARK: - 簡易 Markdown 表示（``` のコードブロック + インライン装飾）

struct MarkdownText: View {
    let text: String

    private enum Segment: Identifiable {
        case prose(Int, String)
        case code(Int, String, String)   // index, 言語, 本文
        var id: Int {
            switch self {
            case .prose(let i, _), .code(let i, _, _): return i
            }
        }
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var prose: [String] = []
        var code: [String] = []
        var lang = ""
        var inCode = false
        func flushProse() {
            let s = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !s.isEmpty { result.append(.prose(result.count, s)) }
            prose = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(result.count, lang, code.joined(separator: "\n")))
                    code = []
                    inCode = false
                } else {
                    flushProse()
                    lang = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "```", with: "")
                    inCode = true
                }
            } else if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if inCode { result.append(.code(result.count, lang, code.joined(separator: "\n"))) }  // 受信途中
        flushProse()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { seg in
                switch seg {
                case .prose(_, let s):
                    Text(Self.attributed(s))
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(_, let lang, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(lang.isEmpty ? "code" : lang).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            CopyButton(text: code)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        ScrollView(.horizontal) {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                }
            }
        }
    }

    static func attributed(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}

// MARK: - 設定

struct SettingsView: View {
    @AppStorage(SettingsKey.defaultModel) private var defaultModel = ChatModel.opus.rawValue
    @AppStorage(SettingsKey.effort) private var effort = Effort.medium.rawValue
    @AppStorage(SettingsKey.systemPrompt) private var systemPrompt = SettingsKey.defaultSystemPrompt

    @State private var keyInput = ""
    @State private var hasKey = Keychain.load() != nil
    @State private var savedMessage = ""

    var body: some View {
        Form {
            Section("Anthropic API キー") {
                HStack {
                    SecureField(hasKey ? "保存済み（変更する場合は入力）" : "sk-ant-…", text: $keyInput)
                    Button("保存") {
                        if Keychain.save(keyInput) {
                            hasKey = Keychain.load() != nil
                            keyInput = ""
                            savedMessage = hasKey ? "キーチェーンに保存しました" : "削除しました"
                        } else {
                            savedMessage = "保存に失敗しました"
                        }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button("削除", role: .destructive) {
                            Keychain.delete()
                            hasKey = false
                            savedMessage = "削除しました"
                        }
                    }
                }
                Text(savedMessage.isEmpty
                     ? "キーは macOS のキーチェーンにだけ保存されます。console.anthropic.com で発行できます。"
                     : savedMessage)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("新しいチャットの初期設定") {
                Picker("モデル", selection: $defaultModel) {
                    ForEach(ChatModel.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("考える深さ", selection: $effort) {
                    ForEach(Effort.allCases) { Text($0.label).tag($0.rawValue) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("システムプロンプト（Claude への前提の指示）")
                    TextEditor(text: $systemPrompt)
                        .font(.body)
                        .frame(height: 90)
                    Text("会話ごとに作成時点の内容で固定されます。変更は次の新しいチャットから。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Text("MyChat v\(appVersion)").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
