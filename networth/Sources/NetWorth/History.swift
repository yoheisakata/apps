import Foundation

struct AccountInfo: Codable, Identifiable, Hashable {
    var id: String
    var org: String
    var name: String
    var currency: String
}

struct Txn: Codable, Identifiable, Hashable {
    var id: String       // "口座ID|取引ID"
    var account: String
    var posted: String   // "yyyy-MM-dd"
    var amount: Double
    var payee: String
    var detail: String
}

// 投資口座の保有銘柄。最新の取得結果だけを保持する(履歴は残高でカバー)。
struct Holding: Codable, Identifiable, Hashable {
    var id: String       // "口座ID|銘柄ID"
    var symbol: String   // ティッカー。529 などティッカーが無い銘柄は空
    var name: String
    var shares: Double
    var marketValue: Double
    var costBasis: Double
}

// 蓄積データ本体。~/Library/Application Support/NetWorth/history.json に保存する。
struct History: Codable {
    var accounts: [AccountInfo] = []
    var balances: [String: [String: Double]] = [:]  // 口座ID -> 日付 -> 残高
    var transactions: [String: Txn] = [:]           // Txn.id -> Txn
    var holdings: [String: [Holding]] = [:]         // 口座ID -> 保有銘柄(最新)
    var lastFetch: Date?
    var isDemo = false

    init() {}

    // 後から増えたキー(holdings など)が無い既存の history.json も
    // デコード失敗で履歴を失わずに読めるよう、全キーを optional 扱いで読む。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([AccountInfo].self, forKey: .accounts) ?? []
        balances = try c.decodeIfPresent([String: [String: Double]].self, forKey: .balances) ?? [:]
        transactions = try c.decodeIfPresent([String: Txn].self, forKey: .transactions) ?? [:]
        holdings = try c.decodeIfPresent([String: [Holding]].self, forKey: .holdings) ?? [:]
        lastFetch = try c.decodeIfPresent(Date.self, forKey: .lastFetch)
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    mutating func apply(_ set: SFAccountSet) {
        if isDemo { self = History() }  // 本番データが来たらデモは破棄
        let today = History.dayFormatter.string(from: Date())
        for a in set.accounts {
            let info = AccountInfo(
                id: a.id,
                org: a.org?.name ?? a.org?.domain ?? "",
                name: a.name,
                currency: a.currency ?? "USD")
            if let i = accounts.firstIndex(where: { $0.id == a.id }) {
                accounts[i] = info
            } else {
                accounts.append(info)
            }
            balances[a.id, default: [:]][today] = a.balance.value
            holdings[a.id] = (a.holdings ?? []).map { h in
                Holding(id: a.id + "|" + h.id,
                        symbol: h.symbol ?? "",
                        name: h.description ?? "",
                        shares: h.shares?.value ?? 0,
                        marketValue: h.marketValue?.value ?? 0,
                        costBasis: h.costBasis?.value ?? 0)
            }
            for t in a.transactions ?? [] {
                let key = a.id + "|" + t.id
                transactions[key] = Txn(
                    id: key,
                    account: a.id,
                    posted: History.dayFormatter.string(
                        from: Date(timeIntervalSince1970: t.posted)),
                    amount: t.amount.value,
                    payee: t.payee ?? "",
                    detail: t.description ?? "")
            }
        }
        accounts.sort { ($0.org, $0.name) < ($1.org, $1.name) }
        lastFetch = Date()
        isDemo = false
    }
}

enum HistoryFile {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetWorth", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("history.json") }

    static func load() -> History {
        guard let data = try? Data(contentsOf: url),
              let h = try? JSONDecoder().decode(History.self, from: data) else {
            return History()
        }
        return h
    }

    static func save(_ h: History) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(h).write(to: url, options: .atomic)
    }
}

// 動作確認用のサンプルデータ(SimpleFIN 契約前でも UI を試せる)。
extension History {
    static func demo() -> History {
        var h = History()
        h.isDemo = true
        h.lastFetch = Date()
        h.accounts = [
            AccountInfo(id: "boa-check", org: "Bank of America", name: "Checking", currency: "USD"),
            AccountInfo(id: "boa-card", org: "Bank of America", name: "Cash Rewards カード", currency: "USD"),
            AccountInfo(id: "fid-401k", org: "Fidelity", name: "401(k)", currency: "USD"),
            AccountInfo(id: "fid-broker", org: "Fidelity", name: "証券口座", currency: "USD"),
        ]
        let merchants: [(String, ClosedRange<Double>)] = [
            ("WHOLE FOODS MARKET", 30...140), ("COSTCO WHOLESALE", 60...250),
            ("AMAZON.COM", 8...90), ("STARBUCKS", 5...14), ("SHELL OIL", 35...65),
            ("TRADER JOE'S", 20...80), ("UBER EATS", 18...55), ("CVS PHARMACY", 8...40),
            ("NETFLIX.COM", 16...16), ("TARGET", 15...120),
        ]
        var check = 8200.0, card = -420.0, broker = 145_000.0, k401 = 98_000.0
        let cal = Calendar.current
        var txnSeq = 0

        for i in 0..<60 {
            let date = cal.date(byAdding: .day, value: i - 59, to: Date())!
            let iso = History.dayFormatter.string(from: date)
            let dayOfMonth = cal.component(.day, from: date)

            func addTxn(_ account: String, _ amount: Double, _ payee: String, _ detail: String) {
                txnSeq += 1
                let id = "\(account)|demo-\(txnSeq)"
                h.transactions[id] = Txn(id: id, account: account, posted: iso,
                                         amount: amount, payee: payee, detail: detail)
            }

            // カード支出(1日 0〜3 件)
            for _ in 0..<Int.random(in: 0...3) {
                let (name, range) = merchants.randomElement()!
                let amt = (Double.random(in: range) * 100).rounded() / 100
                card -= amt
                addTxn("boa-card", -amt, name, name)
            }
            // 給与(隔週)・家賃(毎月1日)・カード引き落とし(毎月5日)
            if i % 14 == 3 {
                check += 3200
                addTxn("boa-check", 3200, "EMPLOYER PAYROLL", "Direct Deposit")
                k401 += 900
            }
            if dayOfMonth == 1 {
                check -= 2400
                addTxn("boa-check", -2400, "RENT", "Monthly rent")
            }
            if dayOfMonth == 5 {
                let pay = ((-card * 0.9) * 100).rounded() / 100
                check -= pay
                card += pay
                addTxn("boa-check", -pay, "BANK OF AMERICA CARD PAYMENT", "Payment")
            }
            // 投資口座は緩やかなランダムウォーク
            broker *= 1 + Double.random(in: -0.008...0.010)
            k401 *= 1 + Double.random(in: -0.006...0.008)

            h.balances["boa-check", default: [:]][iso] = (check * 100).rounded() / 100
            h.balances["boa-card", default: [:]][iso] = (card * 100).rounded() / 100
            h.balances["fid-broker", default: [:]][iso] = (broker * 100).rounded() / 100
            h.balances["fid-401k", default: [:]][iso] = (k401 * 100).rounded() / 100
        }
        return h
    }
}
