import Foundation
import CryptoKit
import CommonCrypto

enum CryptoError: Error, Equatable {
    case invalidFormat
    case encodingFailed
}

/// マスターパスワードからの鍵導出と、vault本体のAES-256-GCM暗号化/復号を担当する。
///
/// 鍵導出は PBKDF2-HMAC-SHA256（CommonCrypto の CCKeyDerivationPBKDF、外部依存なし）。
/// 以前は CryptoKit の HMAC を Swift ループで60万回まわす自前実装で、解錠のたびに
/// メインスレッドが数秒固まっていた。CommonCrypto 版は同一の鍵を約1/20の時間で導出する
/// （新旧の出力一致は検証済み。既存 vault はそのまま開ける）。
/// 設計書ではArgon2idを推奨しているが、素性の分からないサードパーティ製Argon2ライブラリを
/// 追加するより、Appleのシステムフレームワークだけで完結する方が安全と判断し、
/// このプロトタイプではOWASP推奨の反復回数によるPBKDF2を採用している。
enum CryptoStore {
    static let saltSize = 16
    static let keySize = 32
    static let pbkdf2Iterations = 600_000

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltSize)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltSize, &bytes)
        // 乱数生成の失敗を握りつぶすと all-zero ソルトが静かに生まれるため、続行不能として扱う
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }

    static func deriveKey(password: String, salt: Data, iterations: Int = pbkdf2Iterations) -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: keySize)
        let status = derived.withUnsafeMutableBufferPointer { outPtr -> Int32 in
            salt.withUnsafeBytes { saltPtr -> Int32 in
                passwordBytes.withUnsafeBufferPointer { pwPtr -> Int32 in
                    // 空パスワードでも NULL を渡さないようダミーの非 nil ポインタを使う(長さ 0 なので読まれない)
                    let pwBase = UnsafeRawPointer(pwPtr.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 1)!)
                        .assumingMemoryBound(to: CChar.self)
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBase, passwordBytes.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outPtr.baseAddress, keySize
                    )
                }
            }
        }
        // 失敗を握りつぶすと all-zero 鍵で暗号化してしまうため、続行不能として扱う
        precondition(status == kCCSuccess, "CCKeyDerivationPBKDF failed: \(status)")
        return SymmetricKey(data: Data(derived))
    }

    static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.encodingFailed }
        return combined
    }

    static func decrypt(_ combined: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - エンベロープ暗号化用の鍵ラップ

    /// vault 本体を暗号化するランダムなデータ鍵(DEK)を生成する。
    static func generateDEK() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// DEK を鍵暗号化鍵(KEK)で AES-GCM ラップする。
    static func wrapKey(_ dek: SymmetricKey, using kek: SymmetricKey) throws -> Data {
        let raw = dek.withUnsafeBytes { Data($0) }
        return try encrypt(raw, key: kek)
    }

    /// ラップされた DEK を KEK で復号する。KEK が誤っていれば AES-GCM の検証で throw する。
    static func unwrapKey(_ wrapped: Data, using kek: SymmetricKey) throws -> SymmetricKey {
        let raw = try decrypt(wrapped, key: kek)
        return SymmetricKey(data: raw)
    }

    // MARK: - リカバリーキー

    /// 人が書き写せるリカバリーキーを生成する(Crockford Base32、5文字×5グループ = 125bit)。
    /// 紛らわしい I/L/O/U を除いた 32 文字を使うため、1バイト値の剰余に偏りは出ない(256 が 32 で割り切れる)。
    static func generateRecoveryKey() -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var bytes = [UInt8](repeating: 0, count: 25)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // 失敗を無視すると全部 '0' のキーが生成されてしまうため、続行不能として扱う
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        let chars = bytes.map { alphabet[Int($0) % alphabet.count] }
        return stride(from: 0, to: 25, by: 5)
            .map { String(chars[$0..<$0 + 5]) }
            .joined(separator: "-")
    }

    /// 入力されたリカバリーキーを照合用に正規化する(大文字化・区切り文字や空白を除去)。
    static func normalizeRecoveryKey(_ s: String) -> String {
        String(s.uppercased().filter { $0.isLetter || $0.isNumber })
    }
}
