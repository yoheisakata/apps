import Foundation
import CryptoKit
import AppKit

enum VaultState {
    case noVault
    case locked
    case unlocked
}

/// 一度だけユーザーに提示するリカバリーキー(sheet(item:) 用に Identifiable)。
struct RecoveryKeyDisplay: Identifiable {
    let id = UUID()
    let key: String
    /// 移行やパスワード忘れ以外の、通常作成/再生成のときの文言切り替え用。
    let reason: Reason
    enum Reason { case created, migrated, regenerated }
}

final class VaultModel: ObservableObject {
    @Published var state: VaultState
    @Published var entries: [Entry] = []
    @Published var categories: [Category] = []
    @Published var errorMessage: String?
    @Published var autoLockMinutes: Int = 5 {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: Self.autoLockKey) }
    }
    @Published var lockOnBackground: Bool = true {
        didSet { UserDefaults.standard.set(lockOnBackground, forKey: Self.lockOnBackgroundKey) }
    }

    private static let autoLockKey = "autoLockMinutes"
    private static let lockOnBackgroundKey = "lockOnBackground"

    /// 生成直後に一度だけ表示するリカバリーキー。UI が sheet で提示し、閉じたら nil に戻す。
    @Published var recoveryToShow: RecoveryKeyDisplay?
    /// リカバリーキーで解除した後、新しいマスターパスワードの設定を促すフラグ。
    @Published var needsNewPassword = false

    /// この Mac で Touch ID が使えるか。
    var biometricsAvailable: Bool { BiometricStore.isAvailable }
    /// 指紋解除が有効化済みか。
    @Published var biometricsEnabled: Bool = BiometricStore.isEnabled()

    // エンベロープの構成要素(アンロック中はメモリに保持し、保存時に使い回す)
    private var dek: SymmetricKey?
    private var pwSalt: Data?
    private var pwWrappedKey: Data?
    private var recSalt: Data?
    private var recWrappedKey: Data?

    private var idleTimer: Timer?
    private var lastActivity = Date()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var fallbackCategory: Category {
        categories.first(where: { $0.name == "その他" }) ?? categories.last ?? Category(name: "その他", icon: "folder.fill", isDefault: true)
    }

    func category(for entry: Entry) -> Category {
        guard let id = entry.categoryID else { return fallbackCategory }
        return categories.first(where: { $0.id == id }) ?? fallbackCategory
    }

    init() {
        state = VaultFile.exists() ? .locked : .noVault
        // 保存済みの動作設定を復元(秘密情報ではないので UserDefaults)。didSet を経由しないよう
        // ストレージへ直接読みに行き、未設定ならプロパティ初期値(5分 / ON)のまま。
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.autoLockKey) != nil {
            autoLockMinutes = defaults.integer(forKey: Self.autoLockKey)
        }
        if defaults.object(forKey: Self.lockOnBackgroundKey) != nil {
            lockOnBackground = defaults.bool(forKey: Self.lockOnBackgroundKey)
        }
        setupActivityMonitors()
        setupIdleTimer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    deinit {
        idleTimer?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    @objc private func appDidResignActive() {
        if lockOnBackground { lock() }
    }

    private func setupActivityMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.lastActivity = Date()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }
    }

    private func setupIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, self.state == .unlocked else { return }
            if Date().timeIntervalSince(self.lastActivity) > Double(self.autoLockMinutes * 60) {
                self.lock()
            }
        }
    }

    // MARK: - 作成 / アンロック

    func createVault(password: String) {
        // 新しい vault では、以前の指紋バインディングは無効なので消す
        BiometricStore.disable()
        biometricsEnabled = false
        let dek = CryptoStore.generateDEK()

        let pwSalt = CryptoStore.randomSalt()
        let recovery = CryptoStore.generateRecoveryKey()
        let recSalt = CryptoStore.randomSalt()
        do {
            let pwWrapped = try CryptoStore.wrapKey(dek, using: CryptoStore.deriveKey(password: password, salt: pwSalt))
            let recWrapped = try CryptoStore.wrapKey(dek, using: CryptoStore.deriveKey(password: CryptoStore.normalizeRecoveryKey(recovery), salt: recSalt))

            self.dek = dek
            self.pwSalt = pwSalt
            self.pwWrappedKey = pwWrapped
            self.recSalt = recSalt
            self.recWrappedKey = recWrapped
            self.entries = []
            self.categories = Category.defaultCategories

            try persist()
            state = .unlocked
            errorMessage = nil
            lastActivity = Date()
            recoveryToShow = RecoveryKeyDisplay(key: recovery, reason: .created)
        } catch {
            errorMessage = "作成に失敗しました: \(error.localizedDescription)"
        }
    }

    func unlock(password: String) {
        if VaultFile.isLegacy() {
            migrateLegacy(password: password)
            return
        }
        do {
            let env = try VaultFile.readEnvelope()
            let kek = CryptoStore.deriveKey(password: password, salt: env.pwSalt)
            let dek = try CryptoStore.unwrapKey(env.pwWrappedKey, using: kek)
            try loadVault(env: env, dek: dek)
            state = .unlocked
            errorMessage = nil
            lastActivity = Date()
        } catch {
            errorMessage = "マスターパスワードが違います"
        }
    }

    /// リカバリーキーで vault を解除する。成功後は新しいマスターパスワードの設定を促す。
    func unlockWithRecovery(recoveryKey: String) {
        do {
            let env = try VaultFile.readEnvelope()
            let kek = CryptoStore.deriveKey(password: CryptoStore.normalizeRecoveryKey(recoveryKey), salt: env.recSalt)
            let dek = try CryptoStore.unwrapKey(env.recWrappedKey, using: kek)
            try loadVault(env: env, dek: dek)
            state = .unlocked
            errorMessage = nil
            needsNewPassword = true
            lastActivity = Date()
        } catch {
            errorMessage = "リカバリーキーが違います"
        }
    }

    /// エンベロープと DEK から vault 本体を復号し、メモリ状態を埋める。
    private func loadVault(env: VaultEnvelope, dek: SymmetricKey) throws {
        let plaintext = try CryptoStore.decrypt(env.vault, key: dek)
        try decodeVaultData(plaintext)
        self.dek = dek
        self.pwSalt = env.pwSalt
        self.pwWrappedKey = env.pwWrappedKey
        self.recSalt = env.recSalt
        self.recWrappedKey = env.recWrappedKey
    }

    private func decodeVaultData(_ plaintext: Data) throws {
        let decoder = JSONDecoder()
        if let vaultData = try? decoder.decode(VaultData.self, from: plaintext) {
            self.entries = vaultData.entries
            self.categories = vaultData.categories
        } else {
            // 最初期フォーマット: entries のみの配列
            self.entries = try decoder.decode([Entry].self, from: plaintext)
            self.categories = Category.defaultCategories
        }
    }

    /// 旧 PMV1 vault をパスワードで解除し、リカバリーキー対応の PMV2 へ移行する。
    private func migrateLegacy(password: String) {
        do {
            let (salt, blob) = try VaultFile.readLegacy()
            let oldKey = CryptoStore.deriveKey(password: password, salt: salt)
            let plaintext = try CryptoStore.decrypt(blob, key: oldKey)
            try decodeVaultData(plaintext)

            // 新しい DEK と鍵ラップを組み立てて PMV2 で保存し直す
            let dek = CryptoStore.generateDEK()
            let pwSalt = CryptoStore.randomSalt()
            let recovery = CryptoStore.generateRecoveryKey()
            let recSalt = CryptoStore.randomSalt()
            let pwWrapped = try CryptoStore.wrapKey(dek, using: CryptoStore.deriveKey(password: password, salt: pwSalt))
            let recWrapped = try CryptoStore.wrapKey(dek, using: CryptoStore.deriveKey(password: CryptoStore.normalizeRecoveryKey(recovery), salt: recSalt))

            VaultFile.backupLegacy()   // 念のため移行前ファイルを退避

            self.dek = dek
            self.pwSalt = pwSalt
            self.pwWrappedKey = pwWrapped
            self.recSalt = recSalt
            self.recWrappedKey = recWrapped

            try persist()
            state = .unlocked
            errorMessage = nil
            lastActivity = Date()
            recoveryToShow = RecoveryKeyDisplay(key: recovery, reason: .migrated)
        } catch {
            errorMessage = "マスターパスワードが違います"
        }
    }

    func lock() {
        entries = []
        categories = []
        dek = nil
        pwSalt = nil
        pwWrappedKey = nil
        recSalt = nil
        recWrappedKey = nil
        needsNewPassword = false
        state = .locked
        errorMessage = nil
    }

    /// 最終手段の初期化。マスターパスワードもリカバリーキーも失った場合に、
    /// vault を完全削除して新規作成できる状態に戻す。**保存済みデータはすべて失われる**。
    func resetVault() {
        VaultFile.deleteVault()
        BiometricStore.disable()
        entries = []
        categories = []
        dek = nil
        pwSalt = nil
        pwWrappedKey = nil
        recSalt = nil
        recWrappedKey = nil
        needsNewPassword = false
        recoveryToShow = nil
        biometricsEnabled = false
        errorMessage = nil
        state = .noVault
    }

    // MARK: - 保存

    func save() {
        guard state == .unlocked else { return }
        do {
            try persist()
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    private func persist() throws {
        guard let dek, let pwSalt, let pwWrappedKey, let recSalt, let recWrappedKey else { return }
        let plaintext = try JSONEncoder().encode(VaultData(entries: entries, categories: categories))
        let vaultBlob = try CryptoStore.encrypt(plaintext, key: dek)
        let env = VaultEnvelope(
            pwSalt: pwSalt, pwWrappedKey: pwWrappedKey,
            recSalt: recSalt, recWrappedKey: recWrappedKey,
            vault: vaultBlob
        )
        try VaultFile.writeEnvelope(env)
    }

    // MARK: - 暗号化バックアップ / 復元

    /// 現在の vault を PassMan 専用の暗号化バックアップ(.passmanbackup)としてエンコードする。
    /// 中身は vault.dat と同じエンベロープ暗号化済みデータなので、マスターパスワードか
    /// リカバリーキーが無ければ復号できない。アンロック中のみ書き出せる。
    func exportBackupData() -> Data? {
        guard let pwSalt, let pwWrappedKey, let recSalt, let recWrappedKey, let dek else { return nil }
        do {
            let plaintext = try JSONEncoder().encode(VaultData(entries: entries, categories: categories))
            let vaultBlob = try CryptoStore.encrypt(plaintext, key: dek)
            let env = VaultEnvelope(
                pwSalt: pwSalt, pwWrappedKey: pwWrappedKey,
                recSalt: recSalt, recWrappedKey: recWrappedKey,
                vault: vaultBlob
            )
            return try VaultFile.encodeBackup(env)
        } catch {
            errorMessage = "バックアップの作成に失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    /// PassMan バックアップから復元する。バックアップ作成時のマスターパスワードで
    /// 復号を検証し、成功したら現在の vault.dat を退避してから置き換え、アンロック状態にする。
    /// バックアップの DEK は現在の指紋バインディングと異なるため、指紋解除は無効化する。
    @discardableResult
    func restore(from data: Data, password: String) -> Bool {
        do {
            let env = try VaultFile.decodeBackup(data)
            // バックアップ作成時のマスターパスワードで DEK をアンラップできるか検証する
            let kek = CryptoStore.deriveKey(password: password, salt: env.pwSalt)
            let dek = try CryptoStore.unwrapKey(env.pwWrappedKey, using: kek)

            VaultFile.backupBeforeRestore()      // 上書き前に現在の vault を退避
            try VaultFile.writeEnvelope(env)      // バックアップの内容を正規の vault.dat にする
            BiometricStore.disable()              // 復元した DEK は旧指紋バインディングと不一致
            biometricsEnabled = false

            try loadVault(env: env, dek: dek)
            state = .unlocked
            errorMessage = nil
            lastActivity = Date()
            return true
        } catch let error as CryptoError where error == .invalidFormat {
            errorMessage = "PassMan のバックアップファイルではありません"
            return false
        } catch {
            errorMessage = "パスワードが違うか、バックアップが壊れています"
            return false
        }
    }

    // MARK: - Entries

    func addEntry(_ entry: Entry) {
        entries.append(entry)
        save()
    }

    func updateEntry(_ entry: Entry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.modifiedAt = Date()
        entries[idx] = updated
        save()
    }

    func deleteEntry(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - CSV インポート

    /// ヘッダー付き CSV を取り込む。列名を自動判定して各フィールドにマッピングし、
    /// カテゴリ列があれば既存カテゴリに一致させる(無ければ新規作成)。
    /// タイトル・ログイン名・パスワードが同一の既存エントリーは重複としてスキップする。
    @discardableResult
    func importCSV(_ text: String) -> ImportSummary {
        let rows = CSV.parse(text).filter { row in
            !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        guard rows.count >= 2 else { return ImportSummary(imported: 0, skipped: 0) }

        let header = rows[0].map { CSV.normalize($0) }
        func index(_ aliases: [String]) -> Int? {
            header.firstIndex(where: { aliases.contains($0) })
        }
        let ti = index(CSV.titleAliases)
        let ui = index(CSV.usernameAliases)
        let pi = index(CSV.passwordAliases)
        let urli = index(CSV.urlAliases)
        let ni = index(CSV.noteAliases)
        let hi = index(CSV.hintAliases)
        let ci = index(CSV.categoryAliases)

        var imported = 0
        var skipped = 0

        for row in rows.dropFirst() {
            func value(_ i: Int?) -> String {
                guard let i, i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let username = value(ui)
            let password = value(pi)
            let url = value(urli)
            var title = value(ti)
            if title.isEmpty { title = username.isEmpty ? url : username }

            // 完全に空の行はスキップ
            if title.isEmpty, username.isEmpty, password.isEmpty {
                skipped += 1
                continue
            }
            // 既存の同一エントリーは重複としてスキップ
            if entries.contains(where: { $0.title == title && $0.username == username && $0.password == password }) {
                skipped += 1
                continue
            }

            let categoryID = resolveCategory(named: value(ci))
            let entry = Entry(
                title: title.isEmpty ? "(無題)" : title,
                username: username,
                password: password,
                url: url,
                note: value(ni),
                hint: value(hi),
                categoryID: categoryID
            )
            entries.append(entry)
            imported += 1
        }

        if imported > 0 { save() }
        return ImportSummary(imported: imported, skipped: skipped)
    }

    /// カテゴリ名から categoryID を得る。空なら「その他」。既存に一致すればそれを使い、
    /// 無ければ新しいカテゴリを作成する。
    private func resolveCategory(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackCategory.id }
        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing.id
        }
        let created = Category(name: trimmed, icon: "folder.fill")
        categories.append(created)
        return created.id
    }

    // MARK: - Categories

    func addCategory(_ category: Category) {
        categories.append(category)
        save()
    }

    /// カテゴリの名前・アイコンを更新する。エントリーは categoryID で紐づくので付け替え不要。
    func updateCategory(_ category: Category) {
        guard let idx = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[idx] = category
        save()
    }

    /// サイドバーのドラッグ&ドロップによるカテゴリの並べ替えを保存する。
    func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func deleteCategory(_ category: Category) {
        let fb = fallbackCategory
        for i in entries.indices where entries[i].categoryID == category.id {
            entries[i].categoryID = fb.id
        }
        categories.removeAll { $0.id == category.id }
        save()
    }

    // MARK: - マスターパスワード / リカバリーキー

    /// 設定画面からのパスワード変更。DEK は不変なのでリカバリーキーはそのまま有効。
    func changeMasterPassword(current: String, new: String) -> Bool {
        guard let dek, let pwSalt, let pwWrappedKey else { return false }
        // 現在のパスワードで DEK をアンラップできるか検証
        let currentKek = CryptoStore.deriveKey(password: current, salt: pwSalt)
        guard (try? CryptoStore.unwrapKey(pwWrappedKey, using: currentKek)) != nil else { return false }

        let newSalt = CryptoStore.randomSalt()
        guard let newWrapped = try? CryptoStore.wrapKey(dek, using: CryptoStore.deriveKey(password: new, salt: newSalt)) else { return false }
        self.pwSalt = newSalt
        self.pwWrappedKey = newWrapped
        save()
        return true
    }

    /// リカバリーキー解除後、新しいマスターパスワードを設定する(現在パスワード不要)。
    func resetPasswordAfterRecovery(new: String) -> Bool {
        guard let dek else { return false }
        let newSalt = CryptoStore.randomSalt()
        guard let newWrapped = try? CryptoStore.wrapKey(dek, using: CryptoStore.deriveKey(password: new, salt: newSalt)) else { return false }
        self.pwSalt = newSalt
        self.pwWrappedKey = newWrapped
        needsNewPassword = false
        save()
        return true
    }

    // MARK: - 指紋認証(Touch ID)

    /// 現在アンロック中の vault の DEK を Touch ID 保護付きで保存し、指紋解除を有効化する。
    func enableBiometrics() {
        guard let dek else { return }
        let dekData = dek.withUnsafeBytes { Data($0) }
        biometricsEnabled = BiometricStore.enable(dek: dekData)
    }

    /// 指紋解除を無効化する。
    func disableBiometrics() {
        BiometricStore.disable()
        biometricsEnabled = false
    }

    /// Touch ID で vault を解除する。指紋で DEK を取り出し、そのまま vault を復号する。
    func unlockWithBiometrics() {
        guard let env = try? VaultFile.readEnvelope() else { return }
        BiometricStore.retrieveDEK(reason: "PassMan のロックを解除") { [weak self] dekData in
            guard let self else { return }
            guard let dekData else { return }   // キャンセル・失敗時は静かに戻り、パスワード入力に任せる
            let dek = SymmetricKey(data: dekData)
            do {
                try self.loadVault(env: env, dek: dek)
                self.state = .unlocked
                self.errorMessage = nil
                self.lastActivity = Date()
            } catch {
                // DEK が古い(vault 再作成後など)場合は指紋を無効化してパスワードに誘導
                self.disableBiometrics()
                self.errorMessage = "指紋で解除できませんでした。パスワードを入力してください。"
            }
        }
    }

    /// リカバリーキーを再生成する(旧キーは無効化)。新しいキーを一度だけ提示する。
    func regenerateRecoveryKey() {
        guard let dek else { return }
        let recovery = CryptoStore.generateRecoveryKey()
        let newSalt = CryptoStore.randomSalt()
        guard let wrapped = try? CryptoStore.wrapKey(dek, using: CryptoStore.deriveKey(password: CryptoStore.normalizeRecoveryKey(recovery), salt: newSalt)) else { return }
        self.recSalt = newSalt
        self.recWrappedKey = wrapped
        save()
        recoveryToShow = RecoveryKeyDisplay(key: recovery, reason: .regenerated)
    }
}
