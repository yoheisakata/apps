import Foundation
import SwiftUI

@MainActor
final class FinanceStore: ObservableObject {
    @Published var history = HistoryFile.load() {
        didSet { cachedDashboard = nil }
    }
    @Published var isFetching = false
    @Published var lastError: String?
    // 保有銘柄の現在株価(ティッカー -> 現在値)。取得できた分だけ入る。
    @Published var quotes: [String: QuoteService.Quote] = [:]
    @Published var quotesUpdated: Date?
    // 銘柄ごとの株価推移(ティッカー -> 日次終値)。
    @Published var priceHistory: [String: [QuoteService.PricePoint]] = [:]

    // computed で Keychain を毎回読むと、接続解除しても変更通知が飛ばず
    // ボタンの活性状態が更新されないため、@Published で持つ。
    @Published private(set) var isConfigured = Keychain.load() != nil

    // Dashboard の集計は全取引を走査する重い処理なので、history が変わるまで使い回す
    // (SwiftUI の再描画のたびに再計算しない)。
    private var cachedDashboard: Dashboard?
    var dashboard: Dashboard {
        if let d = cachedDashboard { return d }
        let d = Dashboard(history)
        cachedDashboard = d
        return d
    }

    func refreshIfConfigured() async {
        if isConfigured { await refresh() }
    }

    func refresh() async {
        guard let accessURL = Keychain.load() else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let set = try await SimpleFIN.fetchAccounts(accessURL: accessURL)
            history.apply(set)
            try HistoryFile.save(history)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshQuotes()
    }

    // 保有銘柄カードに表示中の銘柄の現在株価を Yahoo Finance から取得する。
    // 失敗した銘柄は quotes に入らず、表示側が SimpleFIN の同期値のままにする。
    func refreshQuotes() async {
        let symbols = Set(dashboard.holdingGroups.flatMap { $0.rows.map(\.symbol) })
            .filter { !$0.isEmpty }
        guard !symbols.isEmpty else { return }
        async let fetchedQuotes = QuoteService.fetchAll(symbols: Array(symbols))
        // チャートの期間ピッカーが最大3年まで選べるよう、5年分をまとめて取得して
        // クライアント側で期間を絞り込む(選択のたびに再取得しない)。
        async let fetchedHistory = QuoteService.fetchAllHistory(symbols: Array(symbols), range: "5y")
        let q = await fetchedQuotes
        let h = await fetchedHistory
        if !q.isEmpty {
            quotes.merge(q) { _, new in new }
            quotesUpdated = Date()
        }
        if !h.isEmpty {
            priceHistory.merge(h) { _, new in new }
        }
    }

    func connect(setupToken: String) async throws {
        let accessURL = try await SimpleFIN.claim(setupToken: setupToken)
        Keychain.save(accessURL)
        isConfigured = true
        await refresh()
        if let err = lastError {
            throw NSError(domain: "MyNetWorth", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    func loadDemo() {
        history = History.demo()
        try? HistoryFile.save(history)
    }

    func disconnect() {
        Keychain.delete()
        isConfigured = false
    }
}
