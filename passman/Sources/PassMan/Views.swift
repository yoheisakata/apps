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
        // メニューバー「暗号化バックアップ」>「バックアップから復元…」からも起動できる
        .sheet(isPresented: $vault.showingBackupRestore) {
            RestoreBackupView()
        }
    }
}

/// vault を暗号化したまま書き出す。メニューバーの「暗号化バックアップ」から呼ばれる。
func exportBackup(vault: VaultModel) {
    guard let data = vault.exportBackupData() else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: VaultFile.backupFileExtension) ?? .data]
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmm"
    panel.nameFieldStringValue = "PassMan-\(f.string(from: Date())).\(VaultFile.backupFileExtension)"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
        vault.errorMessage = "書き出しに失敗しました: \(error.localizedDescription)"
    }
}

struct LockView: View {
    @EnvironmentObject var vault: VaultModel
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var recoveryKey = ""
    @State private var usingRecovery = false
    @State private var showingReset = false
    @State private var showingRestore = false

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
                RomanSecureField(placeholder: "マスターパスワード", text: $password, onSubmit: submit)
                    .frame(width: 280)

                if isCreating {
                    RomanSecureField(placeholder: "確認のため再入力", text: $confirmPassword, onSubmit: submit)
                        .frame(width: 280)
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

            // 別の Mac から移行してきた場合の入口。作成画面(vault 無し)でも復元できるようにする。
            if !usingRecovery {
                Divider().frame(width: 280)
                Button {
                    showingRestore = true
                } label: {
                    Label(isCreating ? "別のパソコンから移行（バックアップから復元）"
                                     : "バックアップから復元", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingReset) {
            ResetVaultView()
        }
        .sheet(isPresented: $showingRestore) {
            RestoreBackupView()
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
    @State private var editingCategory: Category?
    @State private var selectedCategoryID: UUID?
    @State private var importAlert: ImportAlert?

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
                                Button {
                                    editingCategory = cat
                                } label: {
                                    Label("名前・アイコンを変更", systemImage: "pencil")
                                }
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
                        .onMove { indices, newOffset in
                            vault.moveCategories(from: indices, to: newOffset)
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
                HStack {
                    Image(systemName: cat.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.title).font(.headline)
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
                    Button { importCSV() } label: { Image(systemName: "square.and.arrow.down") }
                        .help("CSVインポート")
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
        // カテゴリを切り替えたら選択中のエントリーを解除し、詳細を空表示に戻す
        .onChange(of: selectedCategoryID) {
            selection = nil
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
        .sheet(item: $editingCategory) { cat in
            CategoryEditView(category: cat)
        }
        .alert("CSVインポート", isPresented: Binding(
            get: { importAlert != nil },
            set: { if !$0 { importAlert = nil } }
        ), presenting: importAlert) { _ in
            Button("OK") { importAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .text, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "取り込む CSV ファイルを選択してください（UTF-8 / Shift-JIS / UTF-16 に対応）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            importAlert = ImportAlert(message: "ファイルを読み込めませんでした")
            return
        }
        // エンコーディングを自動判定(UTF-8 / UTF-16 / Shift-JIS)してから取り込む
        let text = CSV.decodeText(from: data)
        let summary = vault.importCSV(text)
        if summary.imported == 0 && summary.skipped == 0 {
            importAlert = ImportAlert(message: "取り込める行がありませんでした。ヘッダー行（title, username, password …）があるか確認してください。")
        } else {
            importAlert = ImportAlert(message: "\(summary.imported) 件を取り込みました"
                + (summary.skipped > 0 ? "（\(summary.skipped) 件スキップ）" : ""))
        }
    }
}

/// トップ画面のインポート結果アラート(alert(item:) 相当)。
struct ImportAlert: Identifiable {
    let id = UUID()
    let message: String
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
    @State private var showPassword = false

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
            HStack {
                if showPassword {
                    RomanTextField(placeholder: "パスワード", text: $password)
                } else {
                    RomanSecureField(placeholder: "パスワード", text: $password)
                }
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(showPassword ? "パスワードを隠す" : "パスワードを表示")
            }
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

    /// nil なら新規追加、値があればそのカテゴリの編集。
    var category: Category?

    @State private var name = ""
    @State private var selectedIcon = "folder.fill"

    private var isEditing: Bool { category != nil }

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "カテゴリを編集" : "カテゴリを追加").font(.title3).bold()

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
                Button(isEditing ? "保存" : "追加") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            if let category {
                name = category.name
                selectedIcon = category.icon
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if var existing = category {
            existing.name = trimmed
            existing.icon = selectedIcon
            vault.updateCategory(existing)
        } else {
            vault.addCategory(Category(name: trimmed, icon: selectedIcon))
        }
        dismiss()
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
        case .passwordChanged: return "パスワード変更に伴う新しいリカバリーキー"
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

            RomanSecureField(placeholder: "新しいパスワード", text: $newPass)
            RomanSecureField(placeholder: "確認のため再入力", text: $confirmPass)

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
    @State private var regenPass = ""
    @State private var regenError: String?

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
            Text("変更すると vault は新しい鍵で暗号化し直され、新しいリカバリーキーが発行されます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RomanSecureField(placeholder: "現在のパスワード", text: $current)
            RomanSecureField(placeholder: "新しいパスワード", text: $newPass)
            RomanSecureField(placeholder: "新しいパスワード（確認）", text: $confirmPass)

            if let changeError {
                Text(changeError).foregroundStyle(.red).font(.caption)
            }

            Button("変更する") {
                guard newPass.count >= 8 else {
                    changeError = "8文字以上にしてください"; return
                }
                guard newPass == confirmPass else {
                    changeError = "確認用パスワードが一致しません"; return
                }
                if vault.changeMasterPassword(current: current, new: newPass) {
                    changeError = nil
                    current = ""; newPass = ""; confirmPass = ""
                    dismiss()   // 閉じると新しいリカバリーキーのシートが表示される
                } else {
                    changeError = "現在のパスワードが違います"
                }
            }

            Divider()

            Text("リカバリーキー").font(.headline)
            Text("再生成すると vault は新しい鍵で暗号化し直され、以前のリカバリーキーは（古いバックアップに対しても）使えなくなります。確認のため現在のマスターパスワードが必要です。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RomanSecureField(placeholder: "現在のパスワード", text: $regenPass)
            if let regenError {
                Text(regenError).foregroundStyle(.red).font(.caption)
            }
            Button("リカバリーキーを再生成") {
                if vault.regenerateRecoveryKey(currentPassword: regenPass) {
                    regenPass = ""
                    regenError = nil
                    dismiss()   // 閉じると新しいリカバリーキーのシートが表示される
                } else {
                    regenError = "パスワードが違います"
                }
            }
            .disabled(regenPass.isEmpty)

            Text("暗号化バックアップは、メニューバーの「暗号化バックアップ」から書き出し・復元できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
}

/// PassMan バックアップからの復元。ファイルを選び、バックアップ作成時の
/// マスターパスワードで復号して現在の vault を置き換える。
struct RestoreBackupView: View {
    @EnvironmentObject var vault: VaultModel
    @Environment(\.dismiss) private var dismiss

    @State private var pickedURL: URL?
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("バックアップから復元", systemImage: "arrow.clockwise.circle.fill")
                .font(.title3).bold()

            Text("現在の vault は復元内容で **上書き** されます（直前の状態は自動で退避します）。復元にはバックアップを作成したときのマスターパスワードが必要です。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("バックアップファイルを選択…") { pickFile() }
                if let pickedURL {
                    Text(pickedURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            RomanSecureField(placeholder: "バックアップ作成時のマスターパスワード", text: $password, onSubmit: restore)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("復元する", action: restore)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pickedURL == nil || password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: VaultFile.backupFileExtension) ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { pickedURL = panel.url; error = nil }
    }

    private func restore() {
        guard let pickedURL else { return }
        guard let data = try? Data(contentsOf: pickedURL) else {
            error = "ファイルを読み込めませんでした"
            return
        }
        if vault.restore(from: data, password: password) {
            dismiss()
        } else {
            error = vault.errorMessage
        }
    }
}
