import Foundation

enum SimpleFINError: LocalizedError {
    case badToken
    case badAccessURL
    case notConfigured
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badToken: return "セットアップトークンを読み取れません。SimpleFIN Bridge で発行した文字列をそのまま貼り付けてください。"
        case .badAccessURL: return "アクセスURLが不正です。トークンを再発行してやり直してください。"
        case .notConfigured: return "SimpleFIN が未設定です。設定画面でセットアップトークンを登録してください。"
        case .http(let code): return "SimpleFIN サーバーがエラーを返しました (HTTP \(code))"
        }
    }
}

// SimpleFIN の金額は文字列("123.45")で届くが、数値の実装も許容する。
struct SFMoney: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), let d = Double(s) {
            value = d
        } else if let d = try? c.decode(Double.self) {
            value = d
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "金額を解釈できません")
        }
    }
}

struct SFAccountSet: Decodable {
    var errors: [String]?
    var accounts: [SFAccount]
}

struct SFOrg: Decodable {
    var name: String?
    var domain: String?
}

struct SFAccount: Decodable {
    var id: String
    var name: String
    var currency: String?
    var balance: SFMoney
    var org: SFOrg?
    var transactions: [SFTransaction]?
    var holdings: [SFHolding]?
}

// 投資口座の保有銘柄。プロトコル仕様外だが SimpleFIN Bridge が返す拡張フィールド。
struct SFHolding: Decodable {
    var id: String
    var symbol: String?
    var description: String?
    var shares: SFMoney?
    var marketValue: SFMoney?
    var costBasis: SFMoney?

    enum CodingKeys: String, CodingKey {
        case id, symbol, description, shares
        case marketValue = "market_value"
        case costBasis = "cost_basis"
    }
}

struct SFTransaction: Decodable {
    var id: String
    var posted: Double  // Unix 時刻
    var amount: SFMoney
    var payee: String?
    var description: String?
}

enum SimpleFIN {
    // 月ごとの収支グラフ用に、銀行が許す範囲で最大1年分の取引を取得する。
    static let fetchDays = 365

    /// セットアップトークン(base64 の claim URL)をアクセスURLに交換する。交換は一度きり。
    static func claim(setupToken: String) async throws -> String {
        let trimmed = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              let claimString = String(data: data, encoding: .utf8),
              let url = URL(string: claimString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" else {
            throw SimpleFINError.badToken
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (body, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw SimpleFINError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let accessURL = String(decoding: body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard accessURL.hasPrefix("https://") else { throw SimpleFINError.badAccessURL }
        return accessURL
    }

    /// 全口座の残高と直近の取引を取得する。
    static func fetchAccounts(accessURL: String) async throws -> SFAccountSet {
        guard var comps = URLComponents(string: accessURL),
              let user = comps.user, let pass = comps.password else {
            throw SimpleFINError.badAccessURL
        }
        let auth = Data("\(user):\(pass)".utf8).base64EncodedString()
        comps.user = nil
        comps.password = nil
        comps.path += "/accounts"
        let start = Int(Date().addingTimeInterval(-Double(fetchDays) * 86400).timeIntervalSince1970)
        comps.queryItems = [URLQueryItem(name: "start-date", value: String(start))]
        guard let url = comps.url else { throw SimpleFINError.badAccessURL }

        var req = URLRequest(url: url)
        req.setValue("Basic " + auth, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw SimpleFINError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(SFAccountSet.self, from: data)
    }
}
