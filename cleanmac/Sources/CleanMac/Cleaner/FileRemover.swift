import Foundation
import AppKit

/// 削除はすべて「ゴミ箱へ移動」。完全削除は行わない（復元可能）。
enum FileRemover {
    struct Failure: Identifiable {
        let id = UUID()
        let url: URL
        let message: String
    }

    struct Result {
        var trashed: [URL] = []
        var failures: [Failure] = []
    }

    static func moveToTrash(_ urls: [URL]) -> Result {
        var result = Result()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                // trashItem はエラーを投げないまま実際には移動できていないことがある
                // （使用中のファイルなど）ため、消えたかどうかを必ず確認する。
                if FileManager.default.fileExists(atPath: url.path) {
                    result.failures.append(Failure(url: url, message: "ゴミ箱への移動が完了しませんでした（使用中の可能性があります）"))
                } else {
                    result.trashed.append(url)
                }
            } catch {
                result.failures.append(Failure(url: url, message: error.localizedDescription))
            }
        }
        return result
    }

    /// trashItem で失敗した分を Finder 経由（AppleScript）で再試行する。
    /// Finder は root 所有のアプリ（App Store 製など）でも管理者認証を出して
    /// ゴミ箱へ移動でき、他アプリのコンテナも扱える。
    /// 初回は「CleanMac が Finder を制御しようとしています」の許可ダイアログが出る。
    /// NSAppleScript を使うためメインスレッドで呼ぶこと。
    static func retryWithFinder(_ result: Result) -> Result {
        guard !result.failures.isEmpty else { return result }
        var result = result

        let retryURLs = result.failures.map { $0.url }
        let finderError = finderTrash(retryURLs)

        // Finder 実行後に実際に消えたかどうかで成否を判定し直す
        var stillFailed: [Failure] = []
        for failure in result.failures {
            if FileManager.default.fileExists(atPath: failure.url.path) {
                stillFailed.append(Failure(url: failure.url,
                                           message: finderError ?? failure.message))
            } else {
                result.trashed.append(failure.url)
            }
        }
        result.failures = stillFailed
        return result
    }

    /// Finder にゴミ箱への移動を依頼する。エラーがあればメッセージを返す。
    private static func finderTrash(_ urls: [URL]) -> String? {
        let items = urls.map { url -> String in
            let escaped = url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "'", with: "'\\''")
            return "POSIX file \"\(escaped)\""
        }.joined(separator: ", ")
        let source = "tell application \"Finder\" to delete { \(items) }"

        guard let script = NSAppleScript(source: source) else {
            return "AppleScript を作成できませんでした"
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -1743 {
                return "Finder の制御が許可されていません。"
                    + "システム設定 › プライバシーとセキュリティ › オートメーション で"
                    + " CleanMac → Finder をオンにしてください。"
            }
            return errorInfo[NSAppleScript.errorMessage] as? String ?? "Finder での削除に失敗しました"
        }
        return nil
    }
}

extension FileRemover.Result {
    /// 失敗した項目をユーザー向けのエラーメッセージに整形する（失敗がなければ nil）。
    /// `highlight` に含まれる URL は「アプリ本体」、それ以外は「関連ファイル」と表示する。
    func failureMessage(appURLs highlight: Set<URL> = []) -> String? {
        guard !failures.isEmpty else { return nil }
        var lines: [String] = []
        for failure in failures.prefix(8) {
            if highlight.isEmpty {
                lines.append("・\(failure.url.lastPathComponent)\n　→ \(failure.message)")
            } else {
                let kind = highlight.contains(failure.url) ? "アプリ本体" : "関連ファイル"
                lines.append("・\(failure.url.lastPathComponent)（\(kind)）\n　→ \(failure.message)")
            }
        }
        var text = lines.joined(separator: "\n")
        if failures.count > 8 {
            text += "\nほか \(failures.count - 8) 件"
        }
        return text
    }
}
