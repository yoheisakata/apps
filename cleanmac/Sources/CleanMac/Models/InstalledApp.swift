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
