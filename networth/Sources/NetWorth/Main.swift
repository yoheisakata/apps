import SwiftUI

// アプリのバージョン。リリース時はここだけ更新する
// (build_app.sh がこの値を Info.plist にも反映する)。
let appVersion = "0.2.0"

// エントリポイント。`NetWorth --fetch` は UI を出さずに取得だけして終了する
// (launchd から毎朝実行するためのモード)。
@main
struct Main {
    static func main() {
        if CommandLine.arguments.contains("--fetch") {
            headlessFetch()
        } else {
            NetWorthApp.main()
        }
    }

    static func headlessFetch() {
        let sem = DispatchSemaphore(value: 0)
        var ok = true
        Task {
            do {
                guard let accessURL = Keychain.load() else {
                    throw SimpleFINError.notConfigured
                }
                var history = HistoryFile.load()
                let set = try await SimpleFIN.fetchAccounts(accessURL: accessURL)
                history.apply(set)
                try HistoryFile.save(history)
                print("OK: \(set.accounts.count) 口座を取得 (\(Date()))")
            } catch {
                FileHandle.standardError.write(Data("取得失敗: \(error.localizedDescription)\n".utf8))
                ok = false
            }
            sem.signal()
        }
        sem.wait()
        exit(ok ? 0 : 1)
    }
}

struct NetWorthApp: App {
    @StateObject private var store = FinanceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 800, height: 940)
    }
}
