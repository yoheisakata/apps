import Foundation

/// PMV2 のエンベロープ暗号化フォーマット(JSON)。
/// vault 本体はランダムな DEK で暗号化し、その DEK を
/// マスターパスワード由来の KEK とリカバリーキー由来の KEK の両方でラップして保存する。
/// どちらの経路でも DEK を取り出せるので、パスワードを忘れてもリカバリーキーで復旧できる。
struct VaultEnvelope: Codable {
    var version: Int = 2
    var pwSalt: Data          // パスワード KEK 用ソルト
    var pwWrappedKey: Data    // KEK(password) で AES-GCM ラップした DEK
    var recSalt: Data         // リカバリーキー KEK 用ソルト
    var recWrappedKey: Data   // KEK(recovery) で AES-GCM ラップした DEK
    var vault: Data           // DEK で AES-GCM 暗号化した VaultData
}

/// vault.dat の読み書き。新フォーマット(PMV2, JSON)と旧フォーマット(PMV1, バイナリ)の両対応。
///   PMV1: [4 bytes "PMV1"][1 byte version][16 bytes salt][AES-GCM combined]
///   PMV2: JSON('{' 始まり) の VaultEnvelope
/// 先頭バイトで判別する("PMV1" は 0x50…、JSON は 0x7B '{')。
enum VaultFile {
    static let legacyMagic = Data("PMV1".utf8)
    static let legacyVersion: UInt8 = 1

    static var directoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("PassMan", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("vault.dat")
    }

    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// 現在のファイルが旧 PMV1 形式かどうか。
    static func isLegacy() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        return data.prefix(legacyMagic.count) == legacyMagic
    }

    // MARK: - PMV2

    static func writeEnvelope(_ env: VaultEnvelope) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(env)
        try data.write(to: fileURL, options: .atomic)
    }

    static func readEnvelope() throws -> VaultEnvelope {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(VaultEnvelope.self, from: data)
    }

    // MARK: - PMV1(旧フォーマット読み込み・移行用)

    static func readLegacy() throws -> (salt: Data, encryptedBlob: Data) {
        let data = try Data(contentsOf: fileURL)
        let headerSize = legacyMagic.count + 1 + CryptoStore.saltSize
        guard data.count > headerSize, data.prefix(legacyMagic.count) == legacyMagic else {
            throw CryptoError.invalidFormat
        }
        guard data[data.startIndex + legacyMagic.count] == legacyVersion else {
            throw CryptoError.invalidFormat
        }
        let saltStart = data.startIndex + legacyMagic.count + 1
        let salt = data.subdata(in: saltStart..<(saltStart + CryptoStore.saltSize))
        let blob = data.subdata(in: (saltStart + CryptoStore.saltSize)..<data.endIndex)
        return (salt, blob)
    }

    /// 移行前の PMV1 ファイルを保険としてバックアップする。
    static func backupLegacy() {
        let backup = directoryURL.appendingPathComponent("vault.pmv1.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: fileURL, to: backup)
    }

    /// vault 本体と移行バックアップを完全に削除する(初期化用)。
    static func deleteVault() {
        try? FileManager.default.removeItem(at: fileURL)
        let backup = directoryURL.appendingPathComponent("vault.pmv1.bak")
        try? FileManager.default.removeItem(at: backup)
    }
}
