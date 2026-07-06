import Foundation
import SwiftUI

@MainActor
final class FinanceStore: ObservableObject {
    @Published var history = HistoryFile.load()
    @Published var isFetching = false
    @Published var lastError: String?

    var isConfigured: Bool { Keychain.load() != nil }
    var dashboard: Dashboard { Dashboard(history) }

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
    }

    func connect(setupToken: String) async throws {
        let accessURL = try await SimpleFIN.claim(setupToken: setupToken)
        Keychain.save(accessURL)
        await refresh()
        if let err = lastError {
            throw NSError(domain: "NetWorth", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    func loadDemo() {
        history = History.demo()
        try? HistoryFile.save(history)
    }

    func disconnect() {
        Keychain.delete()
    }
}
