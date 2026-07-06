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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                SpendingCard(d: d)
                RecentTxnsCard(d: d)
                if let last = store.history.lastFetch {
                    Text("最終更新: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            if d.points.count < 2 {
                Text("推移グラフは残高の記録が2日分たまると表示されます(毎朝7時に自動記録)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 60)
            } else {
                chart(d)
            }
        }
    }

    @ViewBuilder
    private func chart(_ d: Dashboard) -> some View {
            // AreaMark は0を含むY軸を強制するため、余白込みのドメインを明示して
            // 変化が見えるスケールにする。
            let values = d.points.map(\.total)
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let margin = max((hi - lo) * 0.08, 1)
            Chart(d.points) { p in
                AreaMark(x: .value("日付", p.date),
                         yStart: .value("下限", lo - margin),
                         yEnd: .value("総資産", p.total))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.accentColor.opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("日付", p.date), y: .value("総資産", p.total))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartYScale(domain: (lo - margin)...(hi + margin))
            .frame(height: 170)
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

    var body: some View {
        Card(title: "最近の明細(直近14日)") {
            if d.recentDays.isEmpty {
                Text("直近14日の支出はありません").foregroundStyle(.secondary)
            }
            ForEach(d.recentDays) { g in
                Text("\(g.day)(計 \(usd(g.total)))")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 4)
                ForEach(g.txns) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.payee.isEmpty ? t.detail : t.payee)
                            Text(d.accountNames[t.account] ?? t.account)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(usd(t.amount))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }
                    .font(.callout)
                }
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
