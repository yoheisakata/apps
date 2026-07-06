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

    var points: [Point] = []
    var totalNow = 0.0
    var weekDelta = 0.0
    var monthDelta = 0.0
    var accountRows: [AccountRow] = []
    var spendWeek = 0.0
    var spendPrevWeek = 0.0
    var spendMonth = 0.0
    var topMerchants: [MerchantRow] = []
    var recentDays: [DayGroup] = []
    var accountNames: [String: String] = [:]

    // カード引き落とし・送金・給与など、「支出」に数えない取引のパターン。
    // "chase ach" は追跡済みの住宅ローン引き落とし、"contribution" は 401(k) 内の拠出処理。
    static let transferPattern =
        "card payment|online payment|payment.*thank you|autopay|transfer|xfer|deposit|payroll"
        + "|chase ach|contribution|振替"

    static func isTransfer(_ t: Txn) -> Bool {
        (t.payee + " " + t.detail).range(
            of: transferPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    init(_ h: History) {
        for a in h.accounts { accountNames[a.id] = a.name }

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

        // --- 直近14日の明細を日付ごとに ---
        let recent = spends.filter { $0.posted > ago14 }
        let grouped = Dictionary(grouping: recent, by: \.posted)
        recentDays = grouped.keys.sorted(by: >).map { day in
            let txns = grouped[day]!.sorted { $0.amount < $1.amount }
            return DayGroup(day: day, total: sum(txns), txns: txns)
        }
    }
}
