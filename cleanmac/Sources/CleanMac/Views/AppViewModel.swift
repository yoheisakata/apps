import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var hasScanned = false
    @Published var status = ""
    /// 削除に失敗した項目があるときのエラーダイアログ用メッセージ。
    @Published var errorMessage: String?
    /// 確認ダイアログ用: 削除予定の残存ファイル一覧。
    @Published var pendingLeftovers: [URL] = []

    var selectedApps: [InstalledApp] { apps.filter { $0.isSelected } }
    var selectedSize: Int64 { selectedApps.reduce(0) { $0 + $1.size } }
    var hasSelection: Bool { !selectedApps.isEmpty }

    func scan() async {
        isScanning = true
        status = ""
        let infos = await Task.detached(priority: .userInitiated) {
            AppScanner.scanAll()
        }.value

        apps = infos.map { info in
            var app = InstalledApp(info: info)
            let icon = NSWorkspace.shared.icon(forFile: info.url.path)
            icon.size = NSSize(width: 32, height: 32)
            app.icon = icon
            return app
        }
        hasScanned = true
        isScanning = false
    }

    /// 削除対象アプリに紐づく残存ファイルを事前に集計する。
    func prepareLeftovers() async {
        let queries = selectedApps.map { AppQuery(bundleID: $0.bundleID, name: $0.name) }
        let leftovers = await Task.detached(priority: .userInitiated) {
            queries.flatMap { AppScanner.leftovers(bundleID: $0.bundleID, name: $0.name) }
        }.value
        pendingLeftovers = leftovers
    }

    func uninstall() async {
        isCleaning = true
        let appURLs = selectedApps.map { $0.url }
        let urls = appURLs + pendingLeftovers
        let result = await Task.detached(priority: .userInitiated) {
            FileRemover.moveToTrash(urls)
        }.value
        pendingLeftovers = []
        await scan()
        isCleaning = false

        var message = "\(result.trashed.count) 項目をゴミ箱に移動しました。"
        if !result.failures.isEmpty {
            message += " \(result.failures.count) 項目は移動できませんでした。"
        }
        status = message

        if var detail = result.failureMessage(appURLs: Set(appURLs)) {
            detail += "\n\nアプリが起動中の場合は終了してから再実行してください。"
                + "システム標準アプリや管理者権限が必要なものは Finder から削除してください。"
            errorMessage = detail
        }
    }
}

private struct AppQuery: Sendable {
    let bundleID: String?
    let name: String
}
