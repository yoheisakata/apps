import Foundation
import CryptoKit

enum CryptoError: Error, Equatable {
    case invalidFormat
    case encodingFailed
}

/// マスターパスワードからの鍵導出と、vault本体のAES-256-GCM暗号化/復号を担当する。
///
/// 鍵導出は PBKDF2-HMAC-SHA256（CryptoKitのみで実装、外部依存なし）。
/// 設計書ではArgon2idを推奨しているが、素性の分からないサードパーティ製Argon2ライブラリを
/// 追加するより、Appleのシステムフレームワークだけで完結する方が安全と判断し、
/// このプロトタイプではOWASP推奨の反復回数によるPBKDF2を採用している。
enum CryptoStore {
    static let saltSize = 16
    static let keySize = 32
    static let pbkdf2Iterations = 600_000

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltSize)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltSize, &bytes)
        return Data(bytes)
    }

    static func deriveKey(password: String, salt: Data, iterations: Int = pbkdf2Iterations) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        let counter = withUnsafeBytes(of: UInt32(1).bigEndian) { Data($0) }

        var u = Data(HMAC<SHA256>.authenticationCode(for: salt + counter, using: passwordKey))
        var output = u
        for _ in 1..<iterations {
            u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
            output = xor(output, u)
        }
        return SymmetricKey(data: output.prefix(keySize))
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
        var chars: [Character] = []
        for _ in 0..<25 {
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            chars.append(alphabet[Int(byte) % alphabet.count])
        }
        return stride(from: 0, to: 25, by: 5)
            .map { String(chars[$0..<$0 + 5]) }
            .joined(separator: "-")
    }

    /// 入力されたリカバリーキーを照合用に正規化する(大文字化・区切り文字や空白を除去)。
    static func normalizeRecoveryKey(_ s: String) -> String {
        String(s.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func xor(_ a: Data, _ b: Data) -> Data {
        Data(zip(a, b).map { $0 ^ $1 })
    }
}
