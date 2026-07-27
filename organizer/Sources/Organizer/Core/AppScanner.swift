import Foundation
import AppKit

/// バックグラウンドスキャンで受け渡す軽量情報（Sendable）。
struct AppInfo: Sendable {
    let name: String
    let url: URL
    let bundleID: String?
    let version: String?
    let size: Int64
}

/// 一覧に表示するアプリ（アイコンはメインスレッドで付与）。
struct InstalledApp: Identifiable {
    let id = UUID()
    let info: AppInfo
    var icon: NSImage?
    var isSelected: Bool = false

    var name: String { info.name }
    var url: URL { info.url }
    var size: Int64 { info.size }
    var version: String? { info.version }
    var bundleID: String? { info.bundleID }
}

/// インストール済みアプリの列挙と、アンインストール時の残存ファイル探索。
enum AppScanner {
    static func scanAll() -> [AppInfo] {
        let fm = FileManager.default
        var directories = [URL(fileURLWithPath: "/Applications")]
        let userApps = fm.homeDirectoryForCurrentUser.appending(path: "Applications")
        if fm.fileExists(atPath: userApps.path) {
            directories.append(userApps)
        }

        var apps: [AppInfo] = []
        for dir in directories {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where url.pathExtension == "app" {
                apps.append(makeInfo(url))
            }
        }
        return apps.sorted { $0.size > $1.size }
    }

    private static func makeInfo(_ url: URL) -> AppInfo {
        let bundle = Bundle(url: url)
        let rawName = FileManager.default.displayName(atPath: url.path)
        let name = rawName.hasSuffix(".app") ? String(rawName.dropLast(4)) : rawName
        return AppInfo(
            name: name,
            url: url,
            bundleID: bundle?.bundleIdentifier,
            version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
            size: FileScanner.size(of: url)
        )
    }

    /// アプリに紐づく残存ファイル(サポートデータ・設定・キャッシュ等)を探す。
    /// bundleID 完全一致を優先し、アプリ名一致は取りこぼし補助として使う。
    static func leftovers(bundleID: String?, name: String) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let searchDirs = [
            "Library/Application Support",
            "Library/Caches",
            "Library/Preferences",
            "Library/Logs",
            "Library/Containers",
            "Library/Group Containers",
            "Library/Saved Application State",
            "Library/HTTPStorages",
            "Library/WebKit",
        ].map { home.appending(path: $0) }

        var needles: [String] = []
        if let bundleID, !bundleID.isEmpty { needles.append(bundleID) }
        // 短すぎる名前は誤検出しやすいので除外
        if name.count >= 4 { needles.append(name) }
        guard !needles.isEmpty else { return [] }

        var found: [URL] = []
        for dir in searchDirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries {
                let component = url.lastPathComponent
                let matches = needles.contains { needle in
                    component.localizedCaseInsensitiveContains(needle)
                }
                if matches {
                    found.append(url)
                }
            }
        }
        return found
    }
}
