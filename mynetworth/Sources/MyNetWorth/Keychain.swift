import Foundation
import Security

// SimpleFIN のアクセスURL(読み取り専用の認証情報)を macOS Keychain に保存する。
enum Keychain {
    // MyNetWorth へ改名(2026-08-12)後もサービス名は旧 ID のまま。これは保存済み
    // Keychain 項目の検索キーで、変えると登録済みのアクセスURLが見つからなくなる。
    private static let service = "com.yoheisakata.networth"
    private static let account = "simplefin-access-url"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
