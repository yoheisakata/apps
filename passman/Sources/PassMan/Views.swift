import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var vault: VaultModel

    var body: some View {
        Group {
            switch vault.state {
            case .noVault, .locked:
                LockView()
            case .unlocked:
                MainView()
            }
        }
        .animation(.default, value: vault.state)
        // 生成・移行・再生成の直後に一度だけリカバリーキーを提示する
        .sheet(item: $vault.recoveryToShow) { display in
            RecoveryKeyView(display: display)
        }
        // リカバリーキーで解除した直後は、新しいマスターパスワードの設定を必須にする
        .sheet(isPresented: $vault.needsNewPassword) {
            ResetPasswordView()
                .interactiveDismissDisabled()
        }
    }
}

struct LockView: View {
    @EnvironmentObject var vault: VaultModel
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var recoveryKey = ""
    @State private var usingRecovery = false
    @State private var showingReset = false

    private var isCreating: Bool { vault.state == .noVault }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: usingRecovery ? "key.horizontal.fill" : "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text(titleText)
                .font(.title2).bold()

            if isCreating {
                Text("このパスワードはどこにも保存されません。作成後にリカバリーキーを表示します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
            }

            if usingRecovery {
                Text("作成時に表示されたリカバリーキーを入力してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
                TextField("XXXXX-XXXXX-XXXXX-XXXXX-XXXXX", text: $recoveryKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit(submit)
            } else {
                SecureField("マスターパスワード", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit(submit)

                if isCreating {
                    SecureField("確認のため再入力", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .onSubmit(submit)
                }
            }

            if let error = vault.errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Button(buttonText, action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(submitDisabled)

            if !isCreating && !usingRecovery && vault.biometricsEnabled && vault.biometricsAvailable {
                Button {
                    vault.unlockWithBiometrics()
                } label: {
                    Label("Touch IDで解除", systemImage: "touchid")
                }
                .tint(.blue)
            }

            if !isCreating {
                Button(usingRecovery ? "パスワードで解除する" : "パスワードを忘れた場合") {
                    usingRecovery.toggle()
                    vault.errorMessage = nil
                    password = ""; recoveryKey = ""
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)

                if usingRecovery {
                    Button("リカバリーキーも分からない場合…") { showingReset = true }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingReset) {
            ResetVaultView()
        }
        .onChange(of: vault.state) {
            // 初期化などで状態が変わったらリカバリー入力モードを解除し、入力欄をクリアする
            usingRecovery = false
            password = ""; confirmPassword = ""; recoveryKey = ""
        }
        .onAppear {
            // ロック画面表示時、指紋が有効なら自動で Touch ID を提示する
            if !isCreating && vault.biometricsEnabled && vault.biometricsAvailable {
                vault.unlockWithBiometrics()
            }
        }
    }

    private var titleText: String {
        if isCreating { return "マスターパスワードを設定" }
        return usingRecovery ? "リカバリーキーで解除" : "PassMan"
    }

    private var buttonText: String {
        if isCreating { return "作成してロック解除" }
        return usingRecovery ? "リカバリーキーで解除" : "ロック解除"
    }

    private var submitDisabled: Bool {
        if usingRecovery { return recoveryKey.isEmpty }
        return password.isEmpty || (isCreating && password != confirmPassword)
    }

    private func submit() {
        if usingRecovery {
            vault.unlockWithRecovery(recoveryKey: recoveryKey)
            recoveryKey = ""
            return
        }
        defer { password = ""; confirmPassword = "" }
        if isCreating {
            guard password.count >= 8 else {
                vault.errorMessage = "8文字以上にしてください"
                return
            }
            guard password == confirmPassword else {
                vault.errorMessage = "確認用パスワードが一致しません"
                return
            }
            vault.createVault(password: password)
        } else {
            vault.unlock(password: password)
        }
    }
}

struct MainView: View {
    @EnvironmentObject var vault: VaultModel
    @State private var searchText = ""
    @State private var selection: Entry.ID?
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingAddCategory = false
    @State private var selectedCategoryID: UUID?

    private var filtered: [Entry] {
        var base = vault.entries.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        if let selectedCategoryID {
            base = base.filter { $0.categoryID == selectedCategoryID }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
                || $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func entryCount(for category: Category) -> Int {
        vault.entries.filter { $0.categoryID == category.id }.count
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedCategoryID) {
                    Label("すべて", systemImage: "tray.full.fill")
                        .tag(Optional<UUID>.none)

                    Section("カテゴリ") {
                        ForEach(vault.categories) { cat in
                            HStack {
                                Label(cat.name, systemImage: cat.icon)
                                Spacer()
                                let count = entryCount(for: cat)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                            .tag(Optional(cat.id))
                            .contextMenu {
                                if cat.name != "その他" {
                                    Button(role: .destructive) {
                                        vault.deleteCategory(cat)
                                        if selectedCategoryID == cat.id {
                                            selectedCategoryID = nil
                                        }
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 180)

                Divider()
                Button { showingAddCategory = true } label: {
                    Label("カテゴリを追加", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(180)
        } content: {
            List(filtered, selection: $selection) { entry in
                let cat = vault.category(for: entry)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: cat.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.title).font(.headline)
                    }
                    Text(entry.username).font(.caption).foregroundStyle(.secondary)
                }
                .tag(entry.id)
            }
            .searchable(text: $searchText, prompt: "検索")
            .navigationTitle(selectedCategoryID.flatMap { id in vault.categories.first(where: { $0.id == id })?.name } ?? "すべて")
            .toolbar {
                ToolbarItem {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .help("新規エントリー")
                }
                ToolbarItem {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .help("設定")
                }
                ToolbarItem {
                    Button { vault.lock() } label: { Image(systemName: "lock.fill") }
                        .help("今すぐロック")
                }
            }
        } detail: {
            if let id = selection, let entry = vault.entries.first(where: { $0.id == id }) {
                EntryDetailView(entry: entry)
                    .id(entry.id)
            } else {
                ContentUnavailableView("エントリーを選択してください", systemImage: "key.fill")
            }
        }
        .sheet(isPresented: $showingAdd) {
            EntryEditView(entry: nil)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditView()
        }
    }
}

struct EntryDetailView: View {
    @EnvironmentObject var vault: VaultModel
    var entry: Entry
    @State private var showPassword = false
    @State private var showingEdit = false

    var body: some View {
        let cat = vault.category(for: entry)
        Form {
            Section("サービス") {
                LabeledContent("タイトル", value: entry.title)
                LabeledContent("カテゴリ") {
                    Label(cat.name, systemImage: cat.icon)
                }
                if !entry.url.isEmpty {
                    LabeledContent("URL", value: entry.url)
                }
            }
            Section("ログイン情報") {
                HStack {
                    LabeledContent("ログイン名", value: entry.username)
                    Spacer()
                    Button("コピー") { ClipboardManager.copy(entry.username) }
                }
                HStack {
                    LabeledContent("パスワード", value: showPassword ? entry.password : String(repeating: "•", count: max(entry.password.count, 8)))
                    Spacer()
                    Button(showPassword ? "隠す" : "表示") { showPassword.toggle() }
                    Button("コピー") { ClipboardManager.copy(entry.password, clearAfter: 30) }
                }
                if !entry.hint.isEmpty {
                    LabeledContent("ヒント", value: entry.hint)
                }
            }
            if !entry.note.isEmpty {
                Section("メモ") {
                    Text(entry.note)
                }
            }
            Section {
                Text("更新: \(entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem { Button("編集") { showingEdit = true } }
            ToolbarItem {
                Button(role: .destructive) { vault.deleteEntry(entry) } label: { Text("削除") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EntryEditView(entry: entry)
        }
    }
}

struct EntryEditView: View {
    @EnvironmentObject var vault: VaultModel
    @Environment(\.dismiss) private var dismiss
    var entry: Entry?

    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var note = ""
    @State private var hint = ""
    @State private var categoryID: UUID?

    private var isNew: Bool { entry == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "新規エントリー" : "編集")
                .font(.title3).bold()

            TextField("タイトル", text: $title).textFieldStyle(.roundedBorder)
            Picker("カテゴリ", selection: $categoryID) {
                ForEach(vault.categories) { cat in
                    Label(cat.name, systemImage: cat.icon).tag(Optional(cat.id))
                }
            }
            TextField("ログイン名", text: $username).textFieldStyle(.roundedBorder)
            SecureField("パスワード", text: $password).textFieldStyle(.roundedBorder)
            TextField("ヒント", text: $hint).textFieldStyle(.roundedBorder)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            TextField("メモ", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty || username.isEmpty || password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            if let entry {
                title = entry.title
                username = entry.username
                password = entry.password
                url = entry.url
                note = entry.note
                hint = entry.hint
                categoryID = entry.categoryID
            } else {
                categoryID = vault.fallbackCategory.id
            }
        }
    }

    private func save() {
        if var existing = entry {
            existing.title = title
            existing.username = username
            existing.password = password
            existing.url = url
            existing.note = note
            existing.hint = hint
            existing.categoryID = categoryID
            vault.updateEntry(existing)
        } else {
            vault.addEntry(Entry(title: title, username: username, password: password, url: url, note: note, hint: hint, categoryID: categoryID))
        }
        dismiss()
    }
}

struct CategoryEditView: View {
    @EnvironmentObject var vault: VaultModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "folder.fill"

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("カテゴリを追加").font(.title3).bold()

            TextField("カテゴリ名", text: $name).textFieldStyle(.roundedBorder)

            Text("アイコン").font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Category.availableIcons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedIcon == icon ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("追加") {
                    vault.addCategory(Category(name: name, icon: selectedIcon))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

struct RecoveryKeyView: View {
    @EnvironmentObject var vault: VaultModel
    let display: RecoveryKeyDisplay
    @State private var acknowledged = false

    private var headline: String {
        switch display.reason {
        case .created: return "リカバリーキーを保管してください"
        case .migrated: return "リカバリーキーが発行されました"
        case .regenerated: return "新しいリカバリーキー"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text(headline).font(.title3).bold()

            Text("マスターパスワードを忘れたときは、このキーで vault を解除できます。**この画面を閉じると二度と表示されません。** 紙に書き写すかパスワード以外の安全な場所に保管してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(display.key)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Button {
                ClipboardManager.copy(display.key)
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }

            Toggle("リカバリーキーを安全に保管しました", isOn: $acknowledged)
                .toggleStyle(.checkbox)

            Button("閉じる") {
                vault.recoveryToShow = nil
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!acknowledged)
        }
        .padding(24)
        .frame(width: 380)
    }
}

struct ResetVaultView: View {
    @EnvironmentObject var vault: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""

    private let confirmWord = "初期化"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("すべてのデータを削除して初期化", systemImage: "exclamationmark.triangle.fill")
                .font(.title3).bold()
                .foregroundStyle(.red)

            Text("マスターパスワードもリカバリーキーも分からない場合の最終手段です。保存されているパスワードはすべて **完全に削除** され、復元できません。新しいマスターパスワードで最初から作り直します。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("確認のため「\(confirmWord)」と入力してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(confirmWord, text: $confirmText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button(role: .destructive) {
                    vault.resetVault()
                    dismiss()
                } label: {
                    Text("すべて削除して初期化")
                }
                .disabled(confirmText != confirmWord)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

struct ResetPasswordView: View {
    @EnvironmentObject var vault: VaultModel
    @State private var newPass = ""
    @State private var confirmPass = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新しいマスターパスワード").font(.title3).bold()
            Text("リカバリーキーで解除しました。新しいマスターパスワードを設定してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("新しいパスワード", text: $newPass).textFieldStyle(.roundedBorder)
            SecureField("確認のため再入力", text: $confirmPass).textFieldStyle(.roundedBorder)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("設定する") {
                    guard newPass.count >= 8 else { error = "8文字以上にしてください"; return }
                    guard newPass == confirmPass else { error = "確認用パスワードが一致しません"; return }
                    if !vault.resetPasswordAfterRecovery(new: newPass) {
                        error = "設定に失敗しました"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPass.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

struct SettingsView: View {
    @EnvironmentObject var vault: VaultModel
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPass = ""
    @State private var confirmPass = ""
    @State private var changeError: String?
    @State private var changeSuccess = false
    @State private var importMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("設定").font(.title3).bold()
                .padding(.bottom, 12)

            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
            Stepper("自動ロック: \(vault.autoLockMinutes)分", value: $vault.autoLockMinutes, in: 1...60)
            Toggle("バックグラウンドに移動したらロック", isOn: $vault.lockOnBackground)

            if vault.biometricsAvailable {
                Toggle("Touch IDで解除", isOn: Binding(
                    get: { vault.biometricsEnabled },
                    set: { $0 ? vault.enableBiometrics() : vault.disableBiometrics() }
                ))
            }

            Divider()

            Text("マスターパスワード変更").font(.headline)
            SecureField("現在のパスワード", text: $current).textFieldStyle(.roundedBorder)
            SecureField("新しいパスワード", text: $newPass).textFieldStyle(.roundedBorder)
            SecureField("新しいパスワード（確認）", text: $confirmPass).textFieldStyle(.roundedBorder)

            if let changeError {
                Text(changeError).foregroundStyle(.red).font(.caption)
            }
            if changeSuccess {
                Text("変更しました").foregroundStyle(.green).font(.caption)
            }

            Button("変更する") {
                guard newPass.count >= 8 else {
                    changeError = "8文字以上にしてください"; changeSuccess = false; return
                }
                guard newPass == confirmPass else {
                    changeError = "確認用パスワードが一致しません"; changeSuccess = false; return
                }
                if vault.changeMasterPassword(current: current, new: newPass) {
                    changeError = nil
                    changeSuccess = true
                    current = ""; newPass = ""; confirmPass = ""
                } else {
                    changeError = "現在のパスワードが違います"
                    changeSuccess = false
                }
            }

            Divider()

            Text("リカバリーキー").font(.headline)
            Text("再生成すると、以前のリカバリーキーは使えなくなります。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("リカバリーキーを再生成") {
                dismiss()
                vault.regenerateRecoveryKey()
            }

            Divider()

            Text("CSVインポート").font(.headline)
            Text("ヘッダー付き CSV（Chrome / Safari / 1Password / Bitwarden 等）を取り込みます。列名を自動判定します。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("CSVファイルを選択…") { importCSV() }
            if let importMessage {
                Text(importMessage).font(.caption).foregroundStyle(.green)
            }
              }
              .padding(.vertical, 4)
            }

            Divider().padding(.vertical, 8)
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 360, height: 480)
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .text, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            importMessage = nil
            changeError = "ファイルを読み込めませんでした"
            return
        }
        // BOM を除去して UTF-8 として解釈(不正バイトは置換)
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        let text = String(decoding: bytes, as: UTF8.self)
        let summary = vault.importCSV(text)
        if summary.imported == 0 && summary.skipped == 0 {
            importMessage = "取り込める行がありませんでした"
        } else {
            importMessage = "\(summary.imported) 件を取り込みました"
                + (summary.skipped > 0 ? "（\(summary.skipped) 件スキップ）" : "")
        }
    }
}
