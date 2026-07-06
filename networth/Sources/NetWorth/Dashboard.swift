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
    struct MerchantRow: Identifiable {
        var id: String { name }
        var name: String
        var total: Double
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

    var points: [Point] = []
    var totalNow = 0.0
    var weekDelta = 0.0
    var monthDelta = 0.0
    var accountRows: [AccountRow] = []
    var spendWeek = 0.0
    var spendPrevWeek = 0.0
    var spendMonth = 0.0
    var topMerchants: [MerchantRow] = []
    var daysByMonth: [String: [DayGroup]] = [:]  // "yyyy-MM" -> 日別の支出明細(新しい日が先頭)
    var months: [MonthRow] = []
    var dailySpend: [Point] = []                // 直近30日の日別支出(なしの日は0)
    var incomeByMonth: [String: [IncomeRow]] = [:]  // "yyyy-MM" -> 収入源の内訳
    var spendByMonth: [String: [IncomeRow]] = [:]   // "yyyy-MM" -> 支出先の内訳
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

        // --- 支出集計 ---
        let spends = h.transactions.values.filter { $0.amount < 0 && !Self.isTransfer($0) }
        let ago7 = dayString(ago: 7), ago14 = dayString(ago: 14), ago30 = dayString(ago: 30)
        func sum(_ txns: [Txn]) -> Double { txns.reduce(0) { $0 - $1.amount } }
        let week = spends.filter { $0.posted > ago7 }
        spendWeek = sum(week)
        spendPrevWeek = sum(spends.filter { $0.posted > ago14 && $0.posted <= ago7 })
        spendMonth = sum(spends.filter { $0.posted > ago30 })

        var byPayee: [String: Double] = [:]
        for t in week {
            let name = t.payee.isEmpty ? t.detail : t.payee
            byPayee[name, default: 0] -= t.amount
        }
        topMerchants = byPayee.map { MerchantRow(name: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
            .prefix(5).map { $0 }

        // --- 明細: 月 -> 日別グループ(新しい日が先頭) ---
        let grouped = Dictionary(grouping: spends, by: \.posted)
        let dayGroups = grouped.keys.sorted(by: >).map { day -> DayGroup in
            let txns = grouped[day]!.sorted { $0.amount < $1.amount }
            return DayGroup(day: day, total: sum(txns), txns: txns)
        }
        daysByMonth = Dictionary(grouping: dayGroups) { String($0.day.prefix(7)) }

        // --- 日ごとの支出(直近30日、支出がない日は0で埋める) ---
        var spendByDay: [String: Double] = [:]
        for t in spends where t.posted > ago30 {
            spendByDay[t.posted, default: 0] -= t.amount
        }
        dailySpend = (0..<30).reversed().map { n in
            let day = dayString(ago: n)
            return Point(day: day,
                         date: History.dayFormatter.date(from: day) ?? Date(),
                         total: spendByDay[day] ?? 0)
        }

        // --- 月ごとの収支(直近12ヶ月)と収入の内訳 ---
        // 負債口座(カード・ローン)へのプラス取引は返済の受け側なので収入に数えない。
        let liabilities = Set(h.accounts.map(\.id).filter { (series[$0]?.last ?? 0) < 0 })
        let incomes = h.transactions.values.filter {
            $0.amount > 0 && !liabilities.contains($0.account) && !Self.isIncomeExcluded($0)
        }
        var byMonth: [String: (income: Double, spend: Double)] = [:]
        for t in h.transactions.values where t.amount < 0 && !Self.isTransfer(t) {
            byMonth[String(t.posted.prefix(7)), default: (0, 0)].spend -= t.amount
        }
        for t in incomes {
            byMonth[String(t.posted.prefix(7)), default: (0, 0)].income += t.amount
        }
        months = byMonth.keys.sorted().suffix(12).map { key in
            MonthRow(month: key, income: byMonth[key]!.income, spend: byMonth[key]!.spend)
        }

        func breakdown<S: Sequence>(_ txns: S) -> [String: [IncomeRow]] where S.Element == Txn {
            var src: [String: [String: (count: Int, total: Double)]] = [:]
            for t in txns {
                let m = String(t.posted.prefix(7))
                let name = t.payee.isEmpty ? t.detail : t.payee
                src[m, default: [:]][name, default: (0, 0)].count += 1
                src[m, default: [:]][name, default: (0, 0)].total += abs(t.amount)
            }
            return src.mapValues { dict in
                dict.map { IncomeRow(name: $0.key, count: $0.value.count, total: $0.value.total) }
                    .sorted { $0.total > $1.total }
            }
        }
        incomeByMonth = breakdown(incomes)
        spendByMonth = breakdown(
            h.transactions.values.filter { $0.amount < 0 && !Self.isTransfer($0) })
    }
}
