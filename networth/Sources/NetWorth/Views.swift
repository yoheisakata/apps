import Charts
import SwiftUI

func usd(_ v: Double) -> String {
    v.formatted(.currency(code: "USD"))
}

func usdSigned(_ v: Double) -> String {
    (v >= 0 ? "+" : "") + usd(v)
}

func deltaColor(_ v: Double) -> Color {
    v >= 0 ? .green : .red
}

struct ContentView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showSetup = false

    var body: some View {
        Group {
            if store.history.accounts.isEmpty {
                EmptyStateView(showSetup: $showSetup)
            } else {
                DashboardView()
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .navigationTitle("NetWorth")
        .toolbar {
            ToolbarItemGroup {
                if store.isFetching {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .disabled(!store.isConfigured || store.isFetching)
                .help("SimpleFIN から最新データを取得")

                Button {
                    showSetup = true
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupSheet()
        }
        .task { await store.refreshIfConfigured() }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var store: FinanceStore
    @Binding var showSetup: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text("💰").font(.system(size: 56))
            Text("まだデータがありません").font(.title2.bold())
            Text("SimpleFIN Bridge で銀行を接続し、セットアップトークンを登録すると\n全口座の残高と支出を毎日記録できます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("SimpleFIN を設定…") { showSetup = true }
                    .buttonStyle(.borderedProminent)
                Button("デモデータで試す") { store.loadDemo() }
            }
        }
        .padding(40)
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: FinanceStore

    var body: some View {
        let d = store.dashboard
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let last = store.history.lastFetch {
                    HStack {
                        Spacer()
                        Label("データ取得: \(last.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if store.history.isDemo {
                    Label("デモデータを表示中。SimpleFIN を接続すると実データに切り替わります。",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                if let err = store.lastError {
                    Label(err, systemImage: "xmark.octagon")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView {
                DashboardTab {
                    NetWorthCard(d: d)
                    AccountsCard(groups: d.accountGroups)
                    AlertsCard(alerts: d.alerts)
                    CategoryTrendCard(data: d.monthly)
                }
                .tabItem { Label("メイン", systemImage: "chart.line.uptrend.xyaxis") }

                DashboardTab {
                    CashflowCard(unitLabel: "週", data: d.weekly)
                    BreakdownCard(title: "週の内訳", data: d.weekly)
                    TxnsCard(title: "日毎の支出", d: d, data: d.weekly)
                }
                .tabItem { Label("週", systemImage: "clock") }

                DashboardTab {
                    CashflowCard(unitLabel: "か月", data: d.monthly)
                    BreakdownCard(title: "月の内訳", data: d.monthly)
                    TxnsCard(title: "日毎の支出", d: d, data: d.monthly)
                }
                .tabItem { Label("月", systemImage: "calendar") }

                DashboardTab {
                    StocksCard(d: d)
                    if !d.holdingRows.isEmpty {
                        HoldingsCard(rows: d.holdingRows)
                    }
                }
                .tabItem { Label("投資", systemImage: "chart.bar.xaxis") }
            }
            .padding(.top, 4)
        }
    }
}

// 各タブ共通のスクロールレイアウト。
struct DashboardTab<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
        }
    }
}

private struct Card<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NetWorthCard: View {
    var d: Dashboard
    @AppStorage("includeMortgage") private var includeMortgage = true

    var body: some View {
        let withMortgage = includeMortgage || !d.hasMortgage
        Card(title: "総資産(純資産)") {
            HStack(alignment: .firstTextBaseline) {
                Text(usd(withMortgage ? d.totalNow : d.totalNowExMortgage))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Spacer()
                if d.hasMortgage {
                    Toggle("モーゲージを含める", isOn: $includeMortgage)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.callout)
                }
            }
            HStack(spacing: 12) {
                DeltaChip(label: "今週",
                          value: withMortgage ? d.weekDelta : d.weekDeltaExMortgage)
                DeltaChip(label: "今月",
                          value: withMortgage ? d.monthDelta : d.monthDeltaExMortgage)
            }
            BalanceChart(points: withMortgage ? d.points : d.pointsExMortgage)
        }
    }
}

// 残高推移の折れ線チャート。総資産と株セクションで共用する。
struct BalanceChart: View {
    var points: [Dashboard.Point]
    var height: CGFloat = 170

    var body: some View {
        if points.count < 2 {
            Text("推移グラフは残高の記録が2日分たまると表示されます(毎朝7時に自動記録)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: 60)
        } else {
            // AreaMark は0を含むY軸を強制するため、余白込みのドメインを明示して
            // 変化が見えるスケールにする。
            let values = points.map(\.total)
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let margin = max((hi - lo) * 0.08, 1)
            Chart(points) { p in
                AreaMark(x: .value("日付", p.date),
                         yStart: .value("下限", lo - margin),
                         yEnd: .value("残高", p.total))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.accentColor.opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("日付", p.date), y: .value("残高", p.total))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartYScale(domain: (lo - margin)...(hi + margin))
            .frame(height: height)
        }
    }
}

// 株・投資の推移(最大1年)。保有銘柄カードと同じ個別株口座の残高合計。
struct StocksCard: View {
    var d: Dashboard

    var body: some View {
        Card(title: "株・投資の推移(最大1年)") {
            if d.stocksPoints.isEmpty {
                Text("個別株の口座が見つかりません")
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("保有銘柄の口座合計")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(usd(d.stocksNow))
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                HStack(spacing: 12) {
                    DeltaChip(label: "今週", value: d.stocksWeekDelta)
                    DeltaChip(label: "今月", value: d.stocksMonthDelta)
                }
                BalanceChart(points: Array(d.stocksPoints.suffix(365)), height: 150)
            }
        }
    }
}

// 期間ごとの収支: 収入(上向き棒)・支出(下向き棒)・差引(折れ線)。月・週で共用。
struct CashflowCard: View {
    var unitLabel: String  // "か月" / "週"
    var data: Dashboard.PeriodData

    var body: some View {
        Card(title: "過去\(data.rows.count)\(unitLabel)の推移") {
            if data.rows.isEmpty {
                Text("取引データがたまると表示されます")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 14) {
                    LegendDot(color: .green, label: "収入")
                    LegendDot(color: .red, label: "支出")
                }
                .font(.caption)
                Chart {
                    ForEach(data.rows) { m in
                        BarMark(x: .value("期間", m.month),
                                y: .value("金額", m.income),
                                width: .ratio(0.32))
                            .foregroundStyle(.green.opacity(0.7))
                            .annotation(position: .top, spacing: 2) {
                                Text(usd(m.income))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                            }
                        BarMark(x: .value("期間", m.month),
                                y: .value("金額", -m.spend),
                                width: .ratio(0.32))
                            .foregroundStyle(.red.opacity(0.7))
                            .annotation(position: .bottom, spacing: 2) {
                                Text(usd(m.spend))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.red)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let key = value.as(String.self) {
                                Text(data.labels[key] ?? key)
                            }
                        }
                    }
                }
                .frame(height: 210)
                Text("※ 口座間送金・カード引き落とし・401(k) 拠出は除外。期間の途中は集計中の値です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// 主なカテゴリ別支出の月次推移(折れ線)。上位カテゴリだけを表示する。
struct CategoryTrendCard: View {
    var data: Dashboard.PeriodData  // d.monthly を渡す

    struct Pt: Identifiable {
        var id: String { month + label }
        var month: String
        var label: String
        var total: Double
    }

    // 直近12か月のカテゴリ別合計。12か月合計の上位6カテゴリだけを線にする
    // (「💳 その他」は含めない)。月に支出がないカテゴリは0で埋めて線をつなぐ。
    private func series() -> (labels: [String], points: [Pt]) {
        let months = Array(data.days.keys.sorted().suffix(12))
        var byIcon: [String: [String: Double]] = [:]  // 絵文字 -> 月 -> 合計
        for m in months {
            for t in (data.days[m] ?? []).flatMap(\.txns) {
                byIcon[Dashboard.categoryIcon(t), default: [:]][m, default: 0] -= t.amount
            }
        }
        let names = Dictionary(uniqueKeysWithValues:
            Dashboard.categoryList.map { ($0.icon, $0.label) })
        let top = byIcon.filter { $0.key != "💳" }
            .mapValues { $0.values.reduce(0, +) }
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map(\.key)
        var labels: [String] = []
        var points: [Pt] = []
        for icon in top {
            let label = "\(icon) \(names[icon] ?? "")"
            labels.append(label)
            for m in months {
                points.append(Pt(month: m, label: label, total: byIcon[icon]?[m] ?? 0))
            }
        }
        return (labels, points)
    }

    // "2026-07" → "7月"
    private func monthLabel(_ key: String) -> String {
        Int(key.suffix(2)).map { "\($0)月" } ?? key
    }

    var body: some View {
        Card(title: "主なカテゴリ別支出の推移(過去12か月)") {
            let (labels, points) = series()
            if points.isEmpty {
                Text("取引データがたまると表示されます").foregroundStyle(.secondary)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("月", p.month), y: .value("支出", p.total))
                        .foregroundStyle(by: .value("カテゴリ", p.label))
                        .symbol(by: .value("カテゴリ", p.label))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .chartForegroundStyleScale(
                    domain: labels,
                    range: Array(categoryPalette.prefix(labels.count)))
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let key = value.as(String.self) {
                                Text(monthLabel(key))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 240)
                Text("※ 12か月合計の上位6カテゴリを表示。今月は集計中の値です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// カテゴリ別支出の円グラフ・折れ線で共用する固定パレット(凡例と色を揃える)。
let categoryPalette: [Color] = [
    .blue, .green, .orange, .purple, .pink, .teal,
    .yellow, .red, .indigo, .mint, .cyan, .brown,
]

// 期間を選んで、カテゴリ別支出(円グラフ)と収入・支出の内訳をまとめて見るカード。月・週で共用。
struct BreakdownCard: View {
    var title: String
    var data: Dashboard.PeriodData
    @State private var selectedMonth: String?

    private var currentMonth: String? {
        selectedMonth ?? data.rows.last?.month
    }

    struct Slice: Identifiable {
        var id: String { label }
        var label: String   // "🛒 食料品" など
        var total: Double
    }

    // カテゴリごとの合計(大きい順)。合計の3%未満は「その他」にまとめる。
    private func slices(_ month: String) -> [Slice] {
        let txns = (data.days[month] ?? []).flatMap(\.txns)
        var byIcon: [String: Double] = [:]
        for t in txns {
            byIcon[Dashboard.categoryIcon(t), default: 0] -= t.amount
        }
        let names = Dictionary(uniqueKeysWithValues:
            Dashboard.categoryList.map { ($0.icon, $0.label) })
        let total = byIcon.values.reduce(0, +)
        var main: [Slice] = []
        var other = byIcon["💳"] ?? 0
        for (icon, v) in byIcon where icon != "💳" {
            if v < total * 0.03 {
                other += v
            } else {
                main.append(Slice(label: "\(icon) \(names[icon] ?? "")", total: v))
            }
        }
        main.sort { $0.total > $1.total }
        if other > 0 {
            main.append(Slice(label: "💳 その他", total: other))
        }
        return main
    }

    var body: some View {
        Card(title: title) {
            if let m = currentMonth {
                let income = data.income[m] ?? []
                let spend = data.spend[m] ?? []
                let incomeTotal = income.reduce(0) { $0 + $1.total }
                let spendTotal = spend.reduce(0) { $0 + $1.total }
                HStack(alignment: .center) {
                    Picker("期間", selection: Binding(get: { m }, set: { selectedMonth = $0 })) {
                        ForEach(data.rows.reversed()) { row in
                            Text(data.labels[row.month] ?? row.month).tag(row.month)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    HStack(spacing: 20) {
                        BreakdownStat(label: "収入", value: incomeTotal, color: .green)
                        BreakdownStat(label: "支出", value: spendTotal, color: .red)
                        BreakdownStat(label: "差引", value: incomeTotal - spendTotal,
                                      color: incomeTotal >= spendTotal ? .green : .red,
                                      signed: true)
                    }
                }
                let slices = slices(m)
                if !slices.isEmpty {
                    let total = slices.reduce(0) { $0 + $1.total }
                    Text("カテゴリ別支出")
                        .font(.subheadline.bold())
                        .padding(.top, 6)
                    HStack(alignment: .center, spacing: 24) {
                        Chart(Array(slices.enumerated()), id: \.element.id) { i, s in
                            SectorMark(angle: .value("金額", s.total),
                                       innerRadius: .ratio(0.6),
                                       angularInset: 1.5)
                                .foregroundStyle(categoryPalette[i % categoryPalette.count])
                                .cornerRadius(3)
                        }
                        .frame(width: 190, height: 190)
                        .overlay {
                            VStack(spacing: 1) {
                                Text(usd(total)).font(.headline).monospacedDigit()
                                Text("支出合計").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 5) {
                            ForEach(Array(slices.enumerated()), id: \.element.id) { i, s in
                                GridRow {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(categoryPalette[i % categoryPalette.count])
                                            .frame(width: 9, height: 9)
                                        Text(s.label).lineLimit(1)
                                    }
                                    .gridColumnAlignment(.leading)
                                    Text(usd(s.total)).monospacedDigit()
                                    Text((s.total / total)
                                        .formatted(.percent.precision(.fractionLength(0))))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                        Spacer()
                    }
                }
                Text("収入")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                    .padding(.top, 6)
                BreakdownRows(rows: income, color: .green)
                Text("支出")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                    .padding(.top, 6)
                BreakdownRows(rows: spend, color: .red)
            } else {
                Text("取引データがたまると表示されます").foregroundStyle(.secondary)
            }
        }
    }
}

struct BreakdownStat: View {
    var label: String
    var value: Double
    var color: Color
    var signed = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(signed ? usdSigned(value) : usd(value))
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// 相手先ごとの合計リスト(割合バー付き、上位 maxRows + その他)。
struct BreakdownRows: View {
    var rows: [Dashboard.IncomeRow]
    var color: Color
    var maxRows = 12

    var body: some View {
        if rows.isEmpty {
            Text("この月のデータはありません")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            let maxV = rows.first?.total ?? 1
            ForEach(rows.prefix(maxRows)) { r in
                HStack(spacing: 8) {
                    Text(r.name)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                    if r.count > 1 {
                        Text("×\(r.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule()
                            .fill(color.opacity(0.65))
                            .frame(width: max(6, geo.size.width * r.total / maxV),
                                   height: 10)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    Text(usd(r.total))
                        .monospacedDigit()
                        .frame(width: 100, alignment: .trailing)
                }
                .font(.callout)
                .frame(height: 18)
            }
            if rows.count > maxRows {
                let rest = rows.dropFirst(maxRows)
                HStack {
                    Text("その他 \(rest.count) 件")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(usd(rest.reduce(0) { $0 + $1.total }))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }
}

struct LegendDot: View {
    var color: Color
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct DeltaChip: View {
    var label: String
    var value: Double

    var body: some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text(usdSigned(value))
                .fontWeight(.bold)
                .foregroundStyle(deltaColor(value))
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

struct AccountsCard: View {
    var groups: [Dashboard.AccountGroup]

    var body: some View {
        Card(title: "口座ごとの残高と増減") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 7) {
                GridRow {
                    Text("口座").gridColumnAlignment(.leading)
                    Text("残高")
                    Text("今週")
                    Text("今月")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(groups) { g in
                    // 負債(クレジットカード・モーゲージ)は見出しと残高を赤文字にする。
                    let liability = g.category.isLiability
                    Divider()
                    // カテゴリ見出し行(小計付き)
                    GridRow {
                        Text(g.title)
                            .font(.caption.bold())
                            .foregroundStyle(liability ? Color.red : Color.accentColor)
                        Text(usd(g.total)).monospacedDigit()
                            .foregroundStyle(liability ? .red : .primary)
                        Text(usdSigned(g.week)).monospacedDigit()
                            .foregroundStyle(deltaColor(g.week))
                        Text(usdSigned(g.month)).monospacedDigit()
                            .foregroundStyle(deltaColor(g.month))
                    }
                    .font(.caption.bold())
                    ForEach(g.rows) { r in
                        GridRow {
                            Text(rowName(r, in: g))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help("\(r.info.org) — \(r.info.name)")
                            Text(usd(r.balance)).monospacedDigit()
                                .foregroundStyle(liability ? .red : .primary)
                            Text(usdSigned(r.week)).monospacedDigit()
                                .foregroundStyle(deltaColor(r.week))
                            Text(usdSigned(r.month)).monospacedDigit()
                                .foregroundStyle(deltaColor(r.month))
                        }
                    }
                }
            }
        }
    }

    // 短縮した会社名 + 口座名(番号なし) の1行表示。見出しや口座名と重複する会社名は省く。
    private func rowName(_ r: Dashboard.AccountRow, in g: Dashboard.AccountGroup) -> String {
        let org = Dashboard.orgShort(r.info.org)
        let name = Dashboard.cleanName(r.info.name)
        if org.isEmpty || org == g.title || name.localizedCaseInsensitiveContains(org) {
            return name
        }
        return "\(org) \(name)"
    }
}

// 支出の異常検知の結果一覧。検知はすべてローカルの単純統計(Dashboard.buildAlerts)。
struct AlertsCard: View {
    var alerts: [Dashboard.SpendAlert]

    var body: some View {
        Card(title: "支出アラート(過去30日)") {
            if alerts.isEmpty {
                Label("普段と違う支出は見つかりませんでした", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts) { a in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(a.icon).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.title).font(.callout.weight(.semibold))
                            Text(a.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("※ 二重請求 / 大口(カテゴリの上位5%超) / 月のペース(中央値の1.5倍超) / 定期支払いの金額変化 を検知します。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// SimpleFIN の holdings から作る保有銘柄一覧(全投資口座まとめ、時価の大きい順)。
struct HoldingsCard: View {
    var rows: [Dashboard.HoldingRow]

    var body: some View {
        Card(title: "保有銘柄") {
            HStack {
                Text("\(rows.count)銘柄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(usd(rows.reduce(0) { $0 + $1.marketValue }))
                        .font(.title3.bold())
                        .monospacedDigit()
                    Text("時価合計").font(.caption).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text("銘柄").gridColumnAlignment(.leading)
                    Text("口座").gridColumnAlignment(.leading)
                    Text("株数")
                    Text("時価")
                    Text("損益")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(rows) { r in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.symbol.isEmpty ? r.name : r.symbol)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            if !r.symbol.isEmpty {
                                Text(r.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .gridColumnAlignment(.leading)
                        Text(r.account)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        Text(r.shares.formatted(.number.precision(.fractionLength(0...3))))
                            .monospacedDigit()
                        Text(usd(r.marketValue)).monospacedDigit()
                        // 401(k) などは取得原価が来ない(0)ので損益は出さない。
                        if r.costBasis > 0 {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(usdSigned(r.gain))
                                    .monospacedDigit()
                                    .foregroundStyle(deltaColor(r.gain))
                                Text((r.gain >= 0 ? "+" : "")
                                    + (r.gain / r.costBasis)
                                        .formatted(.percent.precision(.fractionLength(1))))
                                    .font(.caption2)
                                    .foregroundStyle(deltaColor(r.gain))
                            }
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("※ 時価・損益は SimpleFIN の最終同期時点の値です(おおむね1日1回更新)。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct TxnsCard: View {
    var title: String
    var d: Dashboard
    var data: Dashboard.PeriodData
    @State private var selectedMonth: String?
    @State private var expandedDays: Set<String> = []
    @State private var didSetDefault = false
    @State private var keyword = ""
    @State private var category: String?  // categoryIcon の絵文字。nil = すべて
    @State private var account: String?   // 口座フィルター。口座ID / otherAccounts、nil = すべて
    @State private var sort: TxnSort = .date

    // 「その他」(クレジットカード以外の口座すべて)を表すタグ。
    private static let otherAccounts = "__other__"

    // フィルター候補はクレジットカードのみ(短縮名順)。それ以外は「その他」にまとめる。
    private var cardIds: Set<String> {
        Set(d.accountRows.filter { Dashboard.category($0.info) == .card }.map(\.info.id))
    }
    private var cardChoices: [(id: String, name: String)] {
        cardIds.map { ($0, d.accountShort[$0] ?? $0) }.sorted { $0.1 < $1.1 }
    }

    enum TxnSort: String, CaseIterable {
        case date = "日付順"
        case amountDesc = "金額が大きい順"
        case amountAsc = "金額が小さい順"
        case category = "カテゴリ順"
    }

    // フラット表示(日付順以外)の並び替え。カテゴリ順は categoryList の並びでまとめ、
    // 同カテゴリ内は金額が大きい順。
    private func sortedFlat(_ txns: [Txn]) -> [Txn] {
        switch sort {
        case .date:
            return txns
        case .amountDesc:
            return txns.sorted { $0.amount < $1.amount }
        case .amountAsc:
            return txns.sorted { $0.amount > $1.amount }
        case .category:
            let order = Dictionary(uniqueKeysWithValues:
                Dashboard.categoryList.enumerated().map { ($0.element.icon, $0.offset) })
            // カテゴリ推定(正規表現)は比較のたびではなく1件1回で済ませる。
            let keyed: [(txn: Txn, cat: Int)] = txns.map {
                (txn: $0, cat: order[Dashboard.categoryIcon($0)] ?? Int.max)
            }
            let sorted = keyed.sorted { a, b in
                a.cat != b.cat ? a.cat < b.cat : a.txn.amount < b.txn.amount
            }
            return sorted.map(\.txn)
        }
    }

    private var currentMonth: String? {
        selectedMonth ?? data.days.keys.max()
    }

    // "yyyy-MM-dd" → "7/3" のような短い日付表示(金額順の一覧用)。
    private func shortDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
        return "\(m)/\(d)"
    }

    private var filterActive: Bool {
        category != nil || account != nil
            || !keyword.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func matches(_ t: Txn) -> Bool {
        if let a = account {
            if a == Self.otherAccounts {
                if cardIds.contains(t.account) { return false }
            } else if t.account != a {
                return false
            }
        }
        if let c = category, Dashboard.categoryIcon(t) != c { return false }
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty,
           !(t.payee + " " + t.detail).localizedCaseInsensitiveContains(kw) {
            return false
        }
        return true
    }

    var body: some View {
        Card(title: title) {
            let month = currentMonth
            let baseGroups = month.flatMap { data.days[$0] } ?? []
            let groups: [Dashboard.DayGroup] = filterActive
                ? baseGroups.compactMap { g in
                    let txns = g.txns.filter(matches)
                    guard !txns.isEmpty else { return nil }
                    return Dashboard.DayGroup(
                        day: g.day,
                        total: txns.reduce(0) { $0 - $1.amount },
                        txns: txns)
                }
                : baseGroups
            let allExpanded = !groups.isEmpty
                && groups.allSatisfy { expandedDays.contains($0.day) }
            if let m = month {
                HStack {
                    Picker("期間", selection: Binding(
                        get: { m },
                        set: { newMonth in
                            selectedMonth = newMonth
                            // 期間を切り替えたら、その期間の全日を開いた状態にする。
                            expandedDays = Set((data.days[newMonth] ?? []).map(\.day))
                        })) {
                        ForEach(data.days.keys.sorted(by: >), id: \.self) { key in
                            Text(data.labels[key] ?? key).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        expandedDays = allExpanded ? [] : Set(groups.map(\.day))
                    } label: {
                        Label(allExpanded ? "すべて閉じる" : "すべて開く",
                              systemImage: allExpanded
                                  ? "rectangle.compress.vertical"
                                  : "rectangle.expand.vertical")
                            .font(.caption)
                    }
                    .disabled(groups.isEmpty || filterActive || sort != .date)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(usd(groups.reduce(0) { $0 + $1.total }))
                            .font(.title3.bold())
                            .monospacedDigit()
                        Text(filterActive ? "絞り込み合計" : "支出合計")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Picker("並び替え", selection: $sort) {
                        ForEach(TxnSort.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Picker("カテゴリ", selection: $category) {
                        Text("すべてのカテゴリ").tag(String?.none)
                        ForEach(Dashboard.categoryList, id: \.icon) { c in
                            Text("\(c.icon) \(c.label)").tag(String?.some(c.icon))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Picker("口座", selection: $account) {
                        Text("すべての口座").tag(String?.none)
                        ForEach(cardChoices, id: \.id) { a in
                            Text(a.name).tag(String?.some(a.id))
                        }
                        Text("その他").tag(String?.some(Self.otherAccounts))
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("キーワードで絞り込み(店名など)", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    if filterActive {
                        Button("クリア") {
                            category = nil
                            account = nil
                            keyword = ""
                        }
                    }
                    Spacer()
                }
            }
            if groups.isEmpty {
                Text(filterActive ? "条件に合う支出はありません" : "この期間の支出はありません")
                    .foregroundStyle(.secondary)
            }
            if sort != .date {
                // 金額順・カテゴリ順: 日別グループを崩し、期間内の全明細を1本の一覧で表示する。
                let txns = sortedFlat(groups.flatMap(\.txns))
                ForEach(txns) { t in
                    HStack(spacing: 8) {
                        Text(shortDay(t.posted))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)
                        Text(Dashboard.categoryIcon(t))
                            .font(.system(size: 17))
                            .frame(width: 24)
                        Text(t.payee.isEmpty ? t.detail : t.payee)
                            .lineLimit(1)
                        Spacer()
                        Text(d.accountShort[t.account] ?? t.account)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(usd(t.amount))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .font(.callout)
                    .padding(.vertical, 1)
                }
            } else {
                ForEach(groups) { g in
                    DisclosureGroup(isExpanded: Binding(
                        get: { filterActive || expandedDays.contains(g.day) },
                        set: { open in
                            if open { expandedDays.insert(g.day) }
                            else { expandedDays.remove(g.day) }
                        })) {
                        ForEach(g.txns) { t in
                            HStack(spacing: 8) {
                                Text(Dashboard.categoryIcon(t))
                                    .font(.system(size: 17))
                                    .frame(width: 24)
                                Text(t.payee.isEmpty ? t.detail : t.payee)
                                    .lineLimit(1)
                                Spacer()
                                Text(d.accountShort[t.account] ?? t.account)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(usd(t.amount))
                                    .monospacedDigit()
                                    .foregroundStyle(.red)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .font(.callout)
                            .padding(.vertical, 1)
                        }
                    } label: {
                        HStack {
                            Text(g.day)
                                .font(.callout.bold())
                                .foregroundStyle(Color.accentColor)
                            Text("\(g.txns.count)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(usd(g.total))
                                .font(.callout.bold())
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .onAppear {
            // 初期状態は最新期間の全日を開いておく。
            if !didSetDefault, let m = currentMonth {
                expandedDays = Set((data.days[m] ?? []).map(\.day))
                didSetDefault = true
            }
        }
    }
}

struct SetupSheet: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("SimpleFIN の設定").font(.title3.bold())
                Spacer()
                Text("NetWorth v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("1. bridge.simplefin.org でアカウントを作成し、Bank of America / Fidelity を接続\n2. 「New App Connection」でセットアップトークンを発行\n3. 下に貼り付けて「接続」")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("セットアップトークンを貼り付け", text: $token, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Button("デモデータで試す") {
                    store.loadDemo()
                    dismiss()
                }
                if store.isConfigured {
                    Button("接続を解除", role: .destructive) {
                        store.disconnect()
                    }
                }
                Spacer()
                Button("閉じる") { dismiss() }
                Button {
                    busy = true
                    error = nil
                    Task {
                        do {
                            try await store.connect(setupToken: token)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                        busy = false
                    }
                } label: {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("接続")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }

            Text("接続情報は Keychain、履歴データは \(HistoryFile.directory.path) に保存されます。アクセスは読み取り専用です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 480)
    }
}
