import Foundation

// History から画面表示用の集計値をまとめて計算する。
struct Dashboard {
    struct Point: Identifiable {
        var id: String { day }
        var day: String
        var date: Date
        var total: Double
    }
    struct AccountRow: Identifiable {
        var id: String { info.id }
        var info: AccountInfo
        var balance: Double
        var week: Double
        var month: Double
    }
    struct DayGroup: Identifiable {
        var id: String { day }
        var day: String
        var total: Double
        var txns: [Txn]
    }
    struct MonthRow: Identifiable {
        var id: String { month }
        var month: String   // "yyyy-MM"(ソート・X軸用)
        var income: Double
        var spend: Double
        var net: Double { income - spend }
    }
    struct IncomeRow: Identifiable {
        var id: String { name }
        var name: String
        var count: Int
        var total: Double
    }
    struct HoldingRow: Identifiable {
        var id: String
        var account: String  // 短縮口座名
        var symbol: String
        var name: String
        var shares: Double
        var marketValue: Double
        var costBasis: Double
        var gain: Double { marketValue - costBasis }
    }

    var points: [Point] = []
    var totalNow = 0.0
    var weekDelta = 0.0
    var monthDelta = 0.0
    var accountRows: [AccountRow] = []
    // 月・週共通の期間集計。キーは月なら "yyyy-MM"、週なら週初日の "yyyy-MM-dd"。
    struct PeriodData {
        var rows: [MonthRow] = []                 // 期間ごとの収支(古い順)
        var income: [String: [IncomeRow]] = [:]   // 期間 -> 収入源の内訳
        var spend: [String: [IncomeRow]] = [:]    // 期間 -> 支出先の内訳
        var days: [String: [DayGroup]] = [:]      // 期間 -> 日別の支出明細(新しい日が先頭)
        var labels: [String: String] = [:]        // 期間キー -> 表示ラベル
    }

    var monthly = PeriodData()
    var weekly = PeriodData()
    var holdingRows: [HoldingRow] = []          // 全口座の保有銘柄(時価の大きい順)
    var accountPoints: [String: [Point]] = [:]  // 口座ごとの残高推移
    var accountNames: [String: String] = [:]
    var accountShort: [String: String] = [:]    // 明細表示用の短縮名

    // カード引き落とし・送金・給与など、「支出」に数えない取引のパターン。
    // "chase ach" は追跡済みの住宅ローン引き落とし、"contribution" は 401(k) 内の拠出処理。
    static let transferPattern =
        "card payment|online payment|payment.*thank you|autopay|transfer|xfer|deposit|payroll"
        + "|chase ach|contribution|振替"

    static func isTransfer(_ t: Txn) -> Bool {
        (t.payee + " " + t.detail).range(
            of: transferPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // 「収入」に数えないプラス取引(口座間送金・カードへの入金など)。
    // 給与 (payroll/deposit) は収入なので transferPattern と違い除外しない。
    static let incomeExcludePattern =
        "card payment|online payment|payment.*thank you|autopay|transfer|xfer"
        + "|chase ach|contribution|振替"

    static func isIncomeExcluded(_ t: Txn) -> Bool {
        (t.payee + " " + t.detail).range(
            of: incomeExcludePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // 明細用の短縮口座名: "Costco Anywhere Visa® Card by Citi-1676 (1676)" → "Citi •1676"
    static func shortName(_ a: AccountInfo) -> String {
        let orgShort = [
            "Bank of America": "BofA", "Chase Bank": "Chase",
            "Citibank": "Citi", "Fidelity Investments": "Fidelity",
        ]
        let org = orgShort[a.org] ?? a.org
        if let r = a.name.range(of: #"\d{4}\)$"#, options: .regularExpression) {
            return "\(org) •\(a.name[r].dropLast())"
        }
        return org.isEmpty ? a.name : "\(org) \(a.name.prefix(14))"
    }

    // フィルター UI 用のカテゴリ一覧(categoryIcon が返しうる絵文字と表示名)。
    static let categoryList: [(icon: String, label: String)] = [
        ("🛒", "食料品"), ("🍽️", "外食・カフェ"), ("⛽️", "ガソリン"), ("✈️", "旅行"),
        ("🛍️", "買い物"), ("📺", "サブスク"), ("🏥", "医療・薬局"), ("🔨", "住まい・DIY"),
        ("🚗", "交通"), ("🏠", "住居費"), ("💡", "光熱・通信"), ("🎟️", "レジャー"),
        ("💳", "その他"),
    ]

    // カテゴリ推定(ベストエフォート)。上から順に最初にマッチした絵文字を使う。
    static func categoryIcon(_ t: Txn) -> String {
        let s = (t.payee + " " + t.detail).lowercased()
        let rules: [(String, String)] = [
            ("costco gas|shell|chevron|arco|exxon|mobil|76 gas", "⛽️"),
            ("costco|trader joe|whole foods|safeway|qfc|kroger|uwajimaya|h mart|grocer|market",
             "🛒"),
            ("alaska air|delta|united|american air|airline|airbnb|hotel|marriott|hilton|expedia",
             "✈️"),
            ("uber eats|doordash|grubhub|ramen|sushi|restaurant|cafe|coffee|starbucks|pizza"
             + "|grill|chili|dining|bakery|kitchen|bar ", "🍽️"),
            ("netflix|spotify|hulu|disney|youtube|audible|subscription", "📺"),
            ("cvs|walgreens|pharmacy|clinic|dental|medical|psychotherap|hospital|vision", "🏥"),
            ("home depot|lowes|lowe's|ace hardware|ikea", "🔨"),
            ("amazon|target|apple store|apple.com|best buy|walmart", "🛍️"),
            ("uber|lyft|parking|tow |toll|dmv", "🚗"),
            ("rent|mortgage|hoa", "🏠"),
            ("comcast|xfinity|verizon|t-mobile|at&t|electric|water|utility|internet", "💡"),
            ("school|tuition|playtorium|museum|zoo|cinema|amc|theat|game", "🎟️"),
        ]
        for (pat, icon) in rules
        where s.range(of: pat, options: .regularExpression) != nil {
            return icon
        }
        return "💳"
    }

    init(_ h: History) {
        for a in h.accounts {
            accountNames[a.id] = a.name
            accountShort[a.id] = Self.shortName(a)
        }

        // --- 保有銘柄(全口座をまとめて時価の大きい順) ---
        holdingRows = h.holdings.flatMap { acct, list in
            list.filter { $0.marketValue != 0 }.map {
                HoldingRow(id: $0.id,
                           account: accountShort[acct] ?? acct,
                           symbol: $0.symbol,
                           name: $0.name,
                           shares: $0.shares,
                           marketValue: $0.marketValue,
                           costBasis: $0.costBasis)
            }
        }
        .sorted { $0.marketValue > $1.marketValue }

        // --- 残高系列(日付の欠けは直前の値で埋める) ---
        let days = Set(h.balances.values.flatMap { $0.keys }).sorted()
        guard !days.isEmpty else { return }

        var series: [String: [Double]] = [:]
        for (id, byDay) in h.balances {
            var last: Double?
            var out: [Double?] = []
            for d in days {
                if let v = byDay[d] { last = v }
                out.append(last)
            }
            let first = out.compactMap { $0 }.first ?? 0
            series[id] = out.map { $0 ?? first }
        }
        let totals = days.indices.map { i in
            series.values.reduce(0) { $0 + $1[i] }
        }
        points = zip(days, totals).map {
            Point(day: $0, date: History.dayFormatter.date(from: $0) ?? Date(), total: $1)
        }
        for (id, arr) in series {
            accountPoints[id] = zip(days, arr).map {
                Point(day: $0, date: History.dayFormatter.date(from: $0) ?? Date(), total: $1)
            }
        }

        // --- 期間比較のインデックス ---
        let lastDay = days.last!
        let lastDate = History.dayFormatter.date(from: lastDay) ?? Date()
        func dayString(ago n: Int) -> String {
            History.dayFormatter.string(
                from: Calendar.current.date(byAdding: .day, value: -n, to: lastDate)!)
        }
        func index(atOrBefore target: String) -> Int {
            for i in stride(from: days.count - 1, through: 0, by: -1)
            where days[i] <= target { return i }
            return 0
        }
        let iLast = days.count - 1
        let iWeek = index(atOrBefore: dayString(ago: 7))
        let iMonth = index(atOrBefore: dayString(ago: 30))

        totalNow = totals[iLast]
        weekDelta = totals[iLast] - totals[iWeek]
        monthDelta = totals[iLast] - totals[iMonth]

        accountRows = h.accounts.map { a in
            let s = series[a.id] ?? [0]
            let bal = s[min(iLast, s.count - 1)]
            return AccountRow(
                info: a, balance: bal,
                week: bal - s[min(iWeek, s.count - 1)],
                month: bal - s[min(iMonth, s.count - 1)])
        }

        // --- 日別の支出グループ(月・週の明細で共用) ---
        let spends = h.transactions.values.filter { $0.amount < 0 && !Self.isTransfer($0) }
        func sum(_ txns: [Txn]) -> Double { txns.reduce(0) { $0 - $1.amount } }
        let grouped = Dictionary(grouping: spends, by: \.posted)
        let dayGroups = grouped.keys.sorted(by: >).map { day -> DayGroup in
            let txns = grouped[day]!.sorted { $0.amount < $1.amount }
            return DayGroup(day: day, total: sum(txns), txns: txns)
        }

        // --- 期間ごとの収支と内訳(月・週) ---
        // 負債口座(カード・ローン)へのプラス取引は返済の受け側なので収入に数えない。
        let liabilities = Set(h.accounts.map(\.id).filter { (series[$0]?.last ?? 0) < 0 })
        let incomes = h.transactions.values.filter {
            $0.amount > 0 && !liabilities.contains($0.account) && !Self.isIncomeExcluded($0)
        }

        func monthKey(_ day: String) -> String { String(day.prefix(7)) }
        func weekKey(_ day: String) -> String {
            guard let date = History.dayFormatter.date(from: day),
                  let start = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start
            else { return day }
            return History.dayFormatter.string(from: start)
        }
        func weekLabel(_ key: String) -> String {
            guard let date = History.dayFormatter.date(from: key) else { return key }
            let c = Calendar.current.dateComponents([.month, .day], from: date)
            return "\(c.month ?? 0)/\(c.day ?? 0)週"
        }

        func build(keyOf: (String) -> String,
                   label: (String) -> String,
                   limit: Int) -> PeriodData {
            var p = PeriodData()
            var byPeriod: [String: (income: Double, spend: Double)] = [:]
            for t in spends {
                byPeriod[keyOf(t.posted), default: (0, 0)].spend -= t.amount
            }
            for t in incomes {
                byPeriod[keyOf(t.posted), default: (0, 0)].income += t.amount
            }
            p.rows = byPeriod.keys.sorted().suffix(limit).map { key in
                MonthRow(month: key, income: byPeriod[key]!.income, spend: byPeriod[key]!.spend)
            }
            func breakdown(_ txns: [Txn]) -> [String: [IncomeRow]] {
                var src: [String: [String: (count: Int, total: Double)]] = [:]
                for t in txns {
                    let k = keyOf(t.posted)
                    let name = t.payee.isEmpty ? t.detail : t.payee
                    src[k, default: [:]][name, default: (0, 0)].count += 1
                    src[k, default: [:]][name, default: (0, 0)].total += abs(t.amount)
                }
                return src.mapValues { dict in
                    dict.map {
                        IncomeRow(name: $0.key, count: $0.value.count, total: $0.value.total)
                    }
                    .sorted { $0.total > $1.total }
                }
            }
            p.income = breakdown(incomes)
            p.spend = breakdown(spends)
            p.days = Dictionary(grouping: dayGroups) { keyOf($0.day) }
            p.labels = Dictionary(uniqueKeysWithValues: byPeriod.keys.map { ($0, label($0)) })
            return p
        }

        monthly = build(keyOf: monthKey, label: { $0 }, limit: 12)
        weekly = build(keyOf: weekKey, label: weekLabel, limit: 12)
    }
}
