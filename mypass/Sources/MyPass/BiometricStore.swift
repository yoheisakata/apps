import Foundation
import Security
import LocalAuthentication

/// vault のデータ鍵(DEK)を Keychain に保存し、Touch ID でアクセスをゲートする。
///
/// エンベロープ設計により DEK はパスワードを変更しても不変なので、一度保存すれば
/// パスワード変更後も指紋解除が有効なまま。
///
/// 【セキュリティ上の注意】このアプリはローカルの ad-hoc 署名(Developer Team 無し)のため、
/// Secure Enclave 連動の生体認証キーチェーン(データ保護キーチェーン / biometric ACL)は
/// entitlement 不足で使えない(SecItemAdd が -34018 で失敗する)。そこで DEK は通常の
/// ログインキーチェーン(この端末のみ・非同期)に保存し、取り出しの前に
/// LocalAuthentication で Touch ID を必須にすることでアプリ側でゲートしている。
/// つまり生体認証はアプリレベルの保護であり、Secure Enclave による暗号的束縛ではない。
/// networth の SimpleFIN トークン保存と同じ水準。強固な保護経路はマスターパスワードと
/// リカバリーキーが担う。
enum BiometricStore {
    private static let service = "com.yoheisakata.mypass"
    private static let account = "vault-dek-biometric"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// この Mac で Touch ID(生体認証)が使えるか。
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 指紋解除が有効化済み(Keychain に DEK が保存されている)か。
    static func isEnabled() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = false
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// DEK を保存する(指紋解除を有効化)。この端末のみ・iCloud 非同期。
    @discardableResult
    static func enable(dek: Data) -> Bool {
        disable()
        var query = baseQuery
        query[kSecValueData as String] = dek
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// 指紋解除を無効化(Keychain から DEK を削除)。
    static func disable() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Touch ID を提示し、成功したら DEK を取り出す。
    /// キャンセル・失敗・未登録なら nil。コールバックはメインスレッドで呼ぶ。
    static func retrieveDEK(reason: String, completion: @escaping (Data?) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = ""   // パスワードフォールバックは出さない(指紋専用)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            guard success else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            let data = (status == errSecSuccess) ? item as? Data : nil
            DispatchQueue.main.async { completion(data) }
        }
    }
}
