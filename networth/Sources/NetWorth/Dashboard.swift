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
    // メインタブの口座一覧のカテゴリ(表示順)。
    enum AccountCategory: Int, CaseIterable {
        case bank, fidelity, card, mortgage
        var title: String {
            switch self {
            case .bank: return "銀行・株"
            case .fidelity: return "Fidelity"
            case .card: return "クレジットカード"
            case .mortgage: return "モーゲージ"
            }
        }
        // 負債グループ(赤文字で表示する)。
        var isLiability: Bool { self == .card || self == .mortgage }
    }
    struct AccountGroup: Identifiable {
        var id: String { title }
        var category: AccountCategory
        var title: String
        var rows: [AccountRow]
        var total: Double { rows.reduce(0) { $0 + $1.balance } }
        var week: Double { rows.reduce(0) { $0 + $1.week } }
        var month: Double { rows.reduce(0) { $0 + $1.month } }
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
    // モーゲージ口座を除いた純資産(トグルで切り替え)。モーゲージ口座がなければ points と同じ。
    var hasMortgage = false
    var pointsExMortgage: [Point] = []
    var totalNowExMortgage = 0.0
    var weekDeltaExMortgage = 0.0
    var monthDeltaExMortgage = 0.0
    var accountRows: [AccountRow] = []
    var accountGroups: [AccountGroup] = []  // カテゴリ別にまとめた口座一覧
    // 月・週共通の期間集計。キーは月なら "yyyy-MM"、週なら週初日の "yyyy-MM-dd"。
    struct PeriodData {
        var rows: [MonthRow] = []                 // 期間ごとの収支(古い順)
        var income: [String: [IncomeRow]] = [:]   // 期間 -> 収入源の内訳
        var spend: [String: [IncomeRow]] = [:]    // 期間 -> 支出先の内訳
        var days: [String: [DayGroup]] = [:]      // 期間 -> 日別の支出明細(新しい日が先頭)
        var labels: [String: String] = [:]        // 期間キー -> 表示ラベル
    }

    // ローカルで計算する支出の異常検知(二重請求・大口・ペース・サブスク変化)。
    struct SpendAlert: Identifiable {
        var id: String
        var icon: String
        var title: String
        var detail: String
    }

    var monthly = PeriodData()
    var weekly = PeriodData()
    var alerts: [SpendAlert] = []
    var holdingRows: [HoldingRow] = []          // 全口座の保有銘柄(時価の大きい順)
    var accountPoints: [String: [Point]] = [:]  // 口座ごとの残高推移
    var accountShort: [String: String] = [:]    // 明細表示用の短縮名

    // カード引き落とし・送金・給与など、「支出」に数えない取引のパターン。
    // "chase ach" は追跡済みの住宅ローン引き落とし、"american express des" は
    // Amex カードの引き落とし(ACH PMT/RETRY PYMT)、"contribution" は 401(k) 内の拠出処理、
    // "reinvestment" は投資口座内の配当再投資。
    static let transferPattern =
        "card payment|online payment|payment.*thank you|autopay|transfer|xfer|deposit|payroll"
        + "|chase ach|american express des|contribution|reinvestment|振替"

    // 取引ごとに毎回コンパイルすると重いので、正規表現は static let で1回だけ作る。
    private static let transferRegex = try! NSRegularExpression(
        pattern: transferPattern, options: [.caseInsensitive])

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func isTransfer(_ t: Txn) -> Bool {
        matches(transferRegex, t.payee + " " + t.detail)
    }

    // 「収入」に数えないプラス取引(口座間送金・カードへの入金など)。
    // 給与 (payroll/deposit) は収入なので transferPattern と違い除外しない。
    static let incomeExcludePattern =
        "card payment|online payment|payment.*thank you|autopay|transfer|xfer"
        + "|chase ach|contribution|振替"

    private static let incomeExcludeRegex = try! NSRegularExpression(
        pattern: incomeExcludePattern, options: [.caseInsensitive])

    static func isIncomeExcluded(_ t: Txn) -> Bool {
        matches(incomeExcludeRegex, t.payee + " " + t.detail)
    }

    static let orgShortNames = [
        "American Express": "Amex", "Bank of America": "BofA",
        "Charles Schwab US": "Schwab", "Chase Bank": "Chase",
        "Citibank": "Citi", "Fidelity Investments": "Fidelity",
    ]

    static func orgShort(_ org: String) -> String {
        orgShortNames[org] ?? org
    }

    // 口座名から末尾の口座番号(下4桁)を取り除く:
    // "Mai Main (3846)" → "Mai Main"、"...Citi-1676 (1676)" → "...Citi"
    static func cleanName(_ name: String) -> String {
        name.replacingOccurrences(
                of: #"\s*\(\d+\)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(
                of: #"(-|\.{3})\d{3,4}\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // 明細用の短縮口座名。クレジットカードは発行会社名で表示
    // ("Costco Anywhere Visa® Card by Citi-1676 (1676)" → "Citi")。
    // それ以外は口座番号を出さず名前の先頭2語まで ("Mai Main (3846)" → "Mai Main")。
    static func shortName(_ a: AccountInfo) -> String {
        let org = orgShort(a.org)
        if category(a) == .card, !org.isEmpty { return org }
        let words = cleanName(a.name).split(separator: " ").prefix(2).joined(separator: " ")
        return words.isEmpty ? org : words
    }

    // 口座のカテゴリ推定: モーゲージ → Fidelity → カード → それ以外は銀行。
    static func category(_ a: AccountInfo) -> AccountCategory {
        let s = (a.org + " " + a.name).lowercased()
        if s.contains("mortgage") { return .mortgage }
        if a.org.localizedCaseInsensitiveContains("fidelity") { return .fidelity }
        if s.range(of: "visa|credit|card|カード", options: .regularExpression) != nil {
            return .card
        }
        return .bank
    }

    // フィルター UI 用のカテゴリ一覧(categoryIcon が返しうる絵文字と表示名)。
    static let categoryList: [(icon: String, label: String)] = [
        ("🛒", "食料品"), ("🍽️", "外食・カフェ"), ("⛽️", "ガソリン"), ("✈️", "旅行"),
        ("🛍️", "買い物"), ("📺", "サブスク"), ("🏥", "医療・薬局"), ("🔨", "住まい・DIY"),
        ("🚗", "交通"), ("🏠", "住居費"), ("💡", "光熱・通信"), ("🎟️", "レジャー"),
        ("💳", "その他"),
    ]

    // カテゴリ推定のルール。上から順に最初にマッチした絵文字を使う(定義順が優先度)。
    private static let categoryRules: [(re: NSRegularExpression, icon: String)] = [
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
        // "Central Park Tow" は HOA fee の引き落とし(交通の "tow" より先に判定)。
        ("central park tow", "🏠"),
        ("uber|lyft|parking|tow |toll|dmv", "🚗"),
        ("rent|mortgage|hoa", "🏠"),
        ("comcast|xfinity|verizon|t-mobile|at&t|electric|water|utility|internet", "💡"),
        ("school|tuition|playtorium|museum|zoo|cinema|amc|theat|game", "🎟️"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    // カテゴリ推定(ベストエフォート)。
    static func categoryIcon(_ t: Txn) -> String {
        let s = (t.payee + " " + t.detail).lowercased()
        let range = NSRange(s.startIndex..., in: s)
        for (re, icon) in categoryRules
        where re.firstMatch(in: s, range: range) != nil {
            return icon
        }
        return "💳"
    }

    init(_ h: History) {
        for a in h.accounts {
            accountShort[a.id] = Self.shortName(a)
        }

        // --- 保有銘柄(時価の大きい順) ---
        // 表示するのは個別株の口座のみ: Fidelity の Stocks (4806) と Charles Schwab。
        // 401(k)・529・IRA などファンド系は除外(データ自体は全口座分 history に保存している)。
        let holdingsAccounts = Set(h.accounts.filter {
            $0.name.contains("4806") || $0.org.localizedCaseInsensitiveContains("schwab")
        }.map(\.id))
        // 口座列は「会社 口座名」で表示する(短縮名だけだと "Individual" などで
        // どこの口座か分からないため)。
        let infoById = Dictionary(uniqueKeysWithValues: h.accounts.map { ($0.id, $0) })
        holdingRows = h.holdings.filter { holdingsAccounts.contains($0.key) }.flatMap { acct, list in
            let label = infoById[acct].map {
                "\(Self.orgShort($0.org)) \(Self.cleanName($0.name))"
            } ?? acct
            return list.filter { $0.marketValue != 0 }.map {
                HoldingRow(id: $0.id,
                           account: label,
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
        // DateFormatter のパースは遅いので、日付は1回だけ変換して全系列で使い回す。
        let dateByDay = Dictionary(uniqueKeysWithValues:
            days.map { ($0, History.dayFormatter.date(from: $0) ?? Date()) })
        func makePoints(_ values: [Double]) -> [Point] {
            zip(days, values).map { Point(day: $0, date: dateByDay[$0]!, total: $1) }
        }
        points = makePoints(totals)
        let mortgageIds = Set(h.accounts.filter { Self.category($0) == .mortgage }.map(\.id))
        hasMortgage = !mortgageIds.isEmpty
        let totalsEx = days.indices.map { i in
            series.reduce(0) { mortgageIds.contains($1.key) ? $0 : $0 + $1.value[i] }
        }
        pointsExMortgage = makePoints(totalsEx)
        for (id, arr) in series {
            accountPoints[id] = makePoints(arr)
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
        totalNowExMortgage = totalsEx[iLast]
        weekDeltaExMortgage = totalsEx[iLast] - totalsEx[iWeek]
        monthDeltaExMortgage = totalsEx[iLast] - totalsEx[iMonth]

        accountRows = h.accounts.map { a in
            let s = series[a.id] ?? [0]
            let bal = s[min(iLast, s.count - 1)]
            return AccountRow(
                info: a, balance: bal,
                week: bal - s[min(iWeek, s.count - 1)],
                month: bal - s[min(iMonth, s.count - 1)])
        }
        let byCategory = Dictionary(grouping: accountRows) { Self.category($0.info) }
        accountGroups = AccountCategory.allCases.compactMap { c in
            guard let rows = byCategory[c], !rows.isEmpty else { return nil }
            // グループ内は金額の大きい順(負債は絶対値で比較)。
            return AccountGroup(category: c, title: c.title,
                                rows: rows.sorted { abs($0.balance) > abs($1.balance) })
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
        // カードは返金などで一時的に残高がプラスになることがあるため、
        // 残高の符号だけでなくカテゴリでも判定する。
        let liabilities = Set(h.accounts.filter {
            Self.category($0).isLiability || (series[$0.id]?.last ?? 0) < 0
        }.map(\.id))
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
            // 週キーは日付パースを伴い取引ごとに計算すると重いので、日付単位でキャッシュする。
            var keyByDay: [String: String] = [:]
            func key(_ day: String) -> String {
                if let k = keyByDay[day] { return k }
                let k = keyOf(day)
                keyByDay[day] = k
                return k
            }
            var p = PeriodData()
            var byPeriod: [String: (income: Double, spend: Double)] = [:]
            for t in spends {
                byPeriod[key(t.posted), default: (0, 0)].spend -= t.amount
            }
            for t in incomes {
                byPeriod[key(t.posted), default: (0, 0)].income += t.amount
            }
            p.rows = byPeriod.keys.sorted().suffix(limit).map { key in
                MonthRow(month: key, income: byPeriod[key]!.income, spend: byPeriod[key]!.spend)
            }
            func breakdown(_ txns: [Txn]) -> [String: [IncomeRow]] {
                var src: [String: [String: (count: Int, total: Double)]] = [:]
                for t in txns {
                    let k = key(t.posted)
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
            p.days = Dictionary(grouping: dayGroups) { key($0.day) }
            p.labels = Dictionary(uniqueKeysWithValues: byPeriod.keys.map { ($0, label($0)) })
            return p
        }

        monthly = build(keyOf: monthKey, label: { $0 }, limit: 12)
        weekly = build(keyOf: weekKey, label: weekLabel, limit: 12)
        alerts = Self.buildAlerts(spends: spends)
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[Int(Double(sorted.count - 1) * p)]
    }

    // 支出の簡易異常検知。全部ローカルの単純な統計で、過去データと比べて
    // 「普段と違う」ものを直近30日から拾う。
    static func buildAlerts(spends: [Txn]) -> [SpendAlert] {
        var out: [SpendAlert] = []
        let fmt = History.dayFormatter
        let cal = Calendar.current
        let today = Date()
        let recentCut = fmt.string(from: cal.date(byAdding: .day, value: -30, to: today)!)
        func payeeName(_ t: Txn) -> String { t.payee.isEmpty ? t.detail : t.payee }

        // --- 二重請求の可能性: 直近30日で同じ店・同額($5以上)が3日以内に2回 ---
        let recent = spends.filter { $0.posted >= recentCut && -$0.amount >= 5 }
        let samePair = Dictionary(grouping: recent) { "\(payeeName($0))|\($0.amount)" }
        for txns in samePair.values where txns.count >= 2 {
            let days = txns.map(\.posted).sorted()
            for i in 1..<days.count {
                guard let d1 = fmt.date(from: days[i - 1]), let d2 = fmt.date(from: days[i]),
                      d2.timeIntervalSince(d1) <= 3 * 86400 else { continue }
                let t = txns[0]
                out.append(SpendAlert(
                    id: "dup-\(t.id)", icon: "🔁",
                    title: "二重請求の可能性: \(payeeName(t)) \(usd(-t.amount)) ×\(txns.count)",
                    detail: "\(days[i - 1]) と \(days[i]) に同額の請求。意図した買い物か確認を"))
                break
            }
        }

        // --- 大口支出: 直近30日で、同カテゴリの95パーセンタイルを超える$100以上 ---
        let byCat = Dictionary(grouping: spends) { categoryIcon($0) }
        let overallP95 = percentile(spends.map { -$0.amount }.sorted(), 0.95)
        let large = spends
            .filter { t in
                let v = -t.amount
                guard t.posted >= recentCut, v >= 100 else { return false }
                let cat = (byCat[categoryIcon(t)] ?? []).map { -$0.amount }.sorted()
                return v > (cat.count >= 10 ? percentile(cat, 0.95) : overallP95)
            }
            .sorted { $0.amount < $1.amount }
            .prefix(3)
        for t in large {
            out.append(SpendAlert(
                id: "large-\(t.id)", icon: "⚠️",
                title: "大口支出: \(payeeName(t)) \(usd(-t.amount))",
                detail: "\(t.posted) / \(categoryIcon(t)) カテゴリの普段の上位5%を超える金額"))
        }

        // --- 月次ペース警告: 今月のカテゴリ支出が過去の月中央値の1.5倍ペース ---
        let thisMonth = String(fmt.string(from: today).prefix(7))
        let dayOfMonth = cal.component(.day, from: today)
        let daysInMonth = cal.range(of: .day, in: .month, for: today)?.count ?? 30
        if dayOfMonth >= 5 {
            var catMonth: [String: [String: Double]] = [:]  // カテゴリ -> 月 -> 合計
            for t in spends {
                catMonth[categoryIcon(t), default: [:]][String(t.posted.prefix(7)), default: 0]
                    -= t.amount
            }
            for (icon, months) in catMonth {
                let past = months.filter { $0.key != thisMonth }.map(\.value).sorted()
                guard past.count >= 2, let cur = months[thisMonth] else { continue }
                let median = past[past.count / 2]
                let projected = cur / Double(dayOfMonth) * Double(daysInMonth)
                if median >= 50, projected > median * 1.5 {
                    out.append(SpendAlert(
                        id: "pace-\(icon)", icon: icon,
                        title: "ペース警告: このままだと今月 \(usd(projected))",
                        detail: "このカテゴリの普段は \(usd(median))/月。すでに \(usd(cur)) 使用"))
                }
            }
        }

        // --- サブスク金額の変化: 毎月1回・同額の請求が最新月だけ変わった ---
        var payeeMonths: [String: [String: [Double]]] = [:]  // 店 -> 月 -> 金額
        for t in spends {
            payeeMonths[payeeName(t), default: [:]][String(t.posted.prefix(7)), default: []]
                .append(-t.amount)
        }
        for (name, months) in payeeMonths {
            guard months.count >= 3, months.values.allSatisfy({ $0.count == 1 })
            else { continue }
            let vals = months.keys.sorted().map { months[$0]![0] }
            let base = Set(vals.dropLast().map { ($0 * 100).rounded() })
            let last = vals.last!
            if base.count == 1, let b = base.first,
               abs(last - b / 100) > max(1, b / 100 * 0.01) {
                out.append(SpendAlert(
                    id: "sub-\(name)", icon: "📈",
                    title: "定期支払いの金額が変化: \(name)",
                    detail: "毎月 \(usd(b / 100)) → 今月 \(usd(last))"))
            }
        }
        return out
    }
}
