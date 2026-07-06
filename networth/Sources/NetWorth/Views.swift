import Charts
import SwiftUI

func usd(_ v: Double) -> String {
    v.formatted(.currency(code: "USD"))
}

func usdSigned(_ v: Double) -> String {
    (v >= 0 ? "+" : "") + usd(v)
}

// グラフ注釈用の短い表記("$27.4K" など)。
// FormatStyle の .notation(.compactName) は macOS 15+ のため自前で組む。
func usdCompact(_ v: Double) -> String {
    let sign = v < 0 ? "-" : ""
    let a = abs(v)
    if a >= 100_000 { return sign + "$" + String(format: "%.0fK", a / 1000) }
    if a >= 1_000 { return sign + "$" + String(format: "%.1fK", a / 1000) }
    return sign + "$" + String(format: "%.0f", a)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                NetWorthCard(d: d)
                AccountsCard(rows: d.accountRows)
                StocksCard(d: d)
                SpendingCard(d: d)
                MonthlyCashflowCard(d: d)
                MonthlyBreakdownCard(d: d)
                RecentTxnsCard(d: d)
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

    var body: some View {
        Card(title: "総資産(純資産)") {
            Text(usd(d.totalNow))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            HStack(spacing: 12) {
                DeltaChip(label: "今週", value: d.weekDelta)
                DeltaChip(label: "今月", value: d.monthDelta)
            }
            BalanceChart(points: d.points)
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

// 株・投資口座の推移(最大1年)。口座はメニューで切り替えられる。
struct StocksCard: View {
    var d: Dashboard
    @State private var selectedId: String?

    private var currentId: String? {
        selectedId
            ?? d.accountRows.first {
                $0.info.name.localizedCaseInsensitiveContains("stock")
            }?.info.id
            ?? d.accountRows.first?.info.id
    }

    var body: some View {
        Card(title: "株・投資の推移(最大1年)") {
            if let id = currentId, let row = d.accountRows.first(where: { $0.info.id == id }) {
                HStack {
                    Picker("口座", selection: Binding(
                        get: { id }, set: { selectedId = $0 })) {
                        ForEach(d.accountRows) { r in
                            Text("\(r.info.org) — \(r.info.name)").tag(r.info.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Text(usd(row.balance))
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                HStack(spacing: 12) {
                    DeltaChip(label: "今週", value: row.week)
                    DeltaChip(label: "今月", value: row.month)
                }
                BalanceChart(points: Array((d.accountPoints[id] ?? []).suffix(365)),
                             height: 150)
            }
        }
    }
}

// 月ごとの収支: 収入(上向き棒)・支出(下向き棒)・差引(折れ線)。
struct MonthlyCashflowCard: View {
    var d: Dashboard

    var body: some View {
        Card(title: "月ごとの収支") {
            if d.months.isEmpty {
                Text("取引データがたまると表示されます")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 14) {
                    LegendDot(color: .green, label: "収入")
                    LegendDot(color: .red, label: "支出")
                    LegendDot(color: .accentColor, label: "差引(収入−支出)")
                }
                .font(.caption)
                Chart {
                    ForEach(d.months) { m in
                        BarMark(x: .value("月", m.month),
                                y: .value("金額", m.income),
                                width: .ratio(0.32))
                            .foregroundStyle(.green.opacity(0.7))
                            .annotation(position: .top, spacing: 2) {
                                Text(usdCompact(m.income))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                            }
                        BarMark(x: .value("月", m.month),
                                y: .value("金額", -m.spend),
                                width: .ratio(0.32))
                            .foregroundStyle(.red.opacity(0.7))
                            .annotation(position: .bottom, spacing: 2) {
                                Text(usdCompact(m.spend))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.red)
                            }
                        LineMark(x: .value("月", m.month), y: .value("差引", m.net))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("月", m.month), y: .value("差引", m.net))
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(30)
                            .annotation(position: .bottomTrailing, spacing: 3) {
                                Text(usdCompact(m.net))
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                    }
                }
                .frame(height: 210)
                Text("※ 口座間送金・カード引き落とし・401(k) 拠出は除外。月の途中は集計中の値です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// 月を選んで収入と支出の内訳をまとめて見るカード。
struct MonthlyBreakdownCard: View {
    var d: Dashboard
    @State private var selectedMonth: String?

    private var currentMonth: String? {
        selectedMonth ?? d.months.last?.month
    }

    var body: some View {
        Card(title: "月の収支の内訳") {
            if let m = currentMonth {
                let income = d.incomeByMonth[m] ?? []
                let spend = d.spendByMonth[m] ?? []
                let incomeTotal = income.reduce(0) { $0 + $1.total }
                let spendTotal = spend.reduce(0) { $0 + $1.total }
                HStack(alignment: .center) {
                    Picker("月", selection: Binding(get: { m }, set: { selectedMonth = $0 })) {
                        ForEach(d.months.reversed()) { row in
                            Text(row.month).tag(row.month)
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
    var rows: [Dashboard.AccountRow]

    var body: some View {
        Card(title: "口座ごとの残高と増減") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("口座").gridColumnAlignment(.leading)
                    Text("残高")
                    Text("今週")
                    Text("今月")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(rows) { r in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.info.org).font(.caption2).foregroundStyle(.secondary)
                            Text(r.info.name)
                        }
                        .gridColumnAlignment(.leading)
                        Text(usd(r.balance)).monospacedDigit()
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

struct SpendingCard: View {
    var d: Dashboard

    var body: some View {
        Card(title: "支出(カード・引き落とし)") {
            HStack(spacing: 28) {
                SpendStat(label: "今週(直近7日)", value: d.spendWeek)
                SpendStat(label: "先週(その前の7日)", value: d.spendPrevWeek)
                SpendStat(label: "直近30日", value: d.spendMonth)
            }
            if !d.dailySpend.isEmpty {
                Text("日ごとの支出(直近30日)")
                    .font(.subheadline.bold())
                    .padding(.top, 6)
                Chart(d.dailySpend) { p in
                    BarMark(x: .value("日", p.date, unit: .day),
                            y: .value("支出", p.total))
                        .foregroundStyle(.red.opacity(0.65))
                        .cornerRadius(2)
                }
                .frame(height: 110)
            }
            if !d.topMerchants.isEmpty {
                Text("今週の使い先 Top 5")
                    .font(.subheadline.bold())
                    .padding(.top, 6)
                let maxV = d.topMerchants.first?.total ?? 1
                ForEach(d.topMerchants) { m in
                    HStack {
                        Text(m.name)
                            .frame(width: 180, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            Capsule()
                                .fill(.linearGradient(
                                    colors: [.blue, .indigo],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * m.total / maxV),
                                       height: 10)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        Text(usd(m.total))
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                    }
                    .font(.callout)
                    .frame(height: 18)
                }
            }
        }
    }
}

struct SpendStat: View {
    var label: String
    var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(usd(value))
                .font(.title2.bold())
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RecentTxnsCard: View {
    var d: Dashboard
    @State private var selectedMonth: String?
    @State private var expandedDays: Set<String> = []
    @State private var didSetDefault = false

    private var currentMonth: String? {
        selectedMonth ?? d.daysByMonth.keys.max()
    }

    var body: some View {
        Card(title: "月ごとの支出") {
            let month = currentMonth
            let groups = month.flatMap { d.daysByMonth[$0] } ?? []
            let allExpanded = !groups.isEmpty
                && groups.allSatisfy { expandedDays.contains($0.day) }
            if let m = month {
                HStack {
                    Picker("月", selection: Binding(
                        get: { m },
                        set: { newMonth in
                            selectedMonth = newMonth
                            // 月を切り替えたら、その月の最新日だけ開く。
                            expandedDays = Set((d.daysByMonth[newMonth]?.first?.day).map { [$0] } ?? [])
                        })) {
                        ForEach(d.daysByMonth.keys.sorted(by: >), id: \.self) { key in
                            Text(key).tag(key)
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
                    .disabled(groups.isEmpty)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(usd(groups.reduce(0) { $0 + $1.total }))
                            .font(.title3.bold())
                            .monospacedDigit()
                        Text("支出合計").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if groups.isEmpty {
                Text("この月の支出はありません").foregroundStyle(.secondary)
            }
            ForEach(groups) { g in
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedDays.contains(g.day) },
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
        .onAppear {
            // 初期状態は最新月の最新日だけ開いておく。
            if !didSetDefault,
               let m = currentMonth, let first = d.daysByMonth[m]?.first {
                expandedDays = [first.day]
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
            Text("SimpleFIN の設定").font(.title3.bold())
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
