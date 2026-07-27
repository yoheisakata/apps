import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case rename, photos, videos, encode, verify, sync, shortClips, cacheClean, appUninstall, dupPhotos, preflight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rename: return "リネーム"
        case .photos: return "写真整理"
        case .videos: return "動画整理"
        case .encode: return "エンコード"
        case .verify: return "写真検証"
        case .sync: return "同期"
        case .shortClips: return "短い動画検索"
        case .cacheClean: return "キャッシュ掃除"
        case .appUninstall: return "アプリ削除"
        case .dupPhotos: return "重複写真"
        case .preflight: return "依存チェック"
        }
    }

    var icon: String {
        switch self {
        case .rename: return "textformat"
        case .photos: return "photo.on.rectangle"
        case .videos: return "film"
        case .encode: return "arrow.triangle.2.circlepath"
        case .verify: return "checkmark.seal"
        case .sync: return "externaldrive.fill.badge.checkmark"
        case .shortClips: return "timer"
        case .cacheClean: return "sparkles"
        case .appUninstall: return "trash"
        case .dupPhotos: return "photo.on.rectangle.angled"
        case .preflight: return "stethoscope"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .photos
    @StateObject private var jobRunner = JobRunner.shared

    private var missingDeps: [String] {
        ["ffmpeg", "rsync"].filter { !ToolLocator.isAvailable($0) }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label {
                    HStack {
                        Text(item.title)
                        if item == .preflight, !missingDeps.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                } icon: {
                    Image(systemName: item.icon)
                }
                .tag(item)
            }
            .navigationTitle("Organizer")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch selection {
                case .rename: RenamerView()
                case .photos: PhotosView()
                case .videos: VideosView()
                case .encode: EncodeView()
                case .verify: VerifyView()
                case .sync: SyncView()
                case .shortClips: ShortClipsView()
                case .cacheClean: CacheCleanerView()
                case .appUninstall: AppUninstallerView()
                case .dupPhotos: DupPhotosView()
                case .preflight: PreflightView()
                case .none: Text("左のメニューから選んでください")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 600, minHeight: 620)
            .safeAreaInset(edge: .bottom) {
                StatusBarView(jobRunner: jobRunner)
            }
        }
    }
}
