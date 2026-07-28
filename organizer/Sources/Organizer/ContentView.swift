import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case rename, photos, videos, encode, misplacedFix, sync, shortClips, cacheClean, appUninstall, dupPhotos, videoDup, videoMaker, preflight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rename: return "リネーム"
        case .photos: return "写真整理"
        case .videos: return "動画整理"
        case .encode: return "エンコード"
        case .misplacedFix: return "誤配置修正"
        case .sync: return "同期"
        case .shortClips: return "短い動画検索"
        case .cacheClean: return "キャッシュ掃除"
        case .appUninstall: return "アプリ削除"
        case .dupPhotos: return "重複写真"
        case .videoDup: return "動画重複"
        case .videoMaker: return "まとめ動画"
        case .preflight: return "依存チェック"
        }
    }

    var icon: String {
        switch self {
        case .rename: return "textformat"
        case .photos: return "photo.on.rectangle"
        case .videos: return "film"
        case .encode: return "arrow.triangle.2.circlepath"
        case .misplacedFix: return "wrench.and.screwdriver"
        case .sync: return "externaldrive.fill.badge.checkmark"
        case .shortClips: return "timer"
        case .cacheClean: return "sparkles"
        case .appUninstall: return "trash"
        case .dupPhotos: return "photo.on.rectangle.angled"
        case .videoDup: return "film.stack"
        case .videoMaker: return "movieclapper"
        case .preflight: return "stethoscope"
        }
    }
}

private let sidebarGroups: [(title: String, items: [SidebarItem])] = [
    ("画像系", [.photos, .misplacedFix, .dupPhotos]),
    ("動画系", [.videos, .encode, .shortClips, .videoDup, .videoMaker]),
    ("その他", [.rename, .sync, .cacheClean, .appUninstall, .preflight]),
]

struct ContentView: View {
    @State private var selection: SidebarItem? = .photos
    @StateObject private var jobRunner = JobRunner.shared

    private var missingDeps: [String] {
        ["ffmpeg", "rsync"].filter { !ToolLocator.isAvailable($0) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sidebarGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
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
                    }
                }
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
                case .misplacedFix: MisplacedFixView()
                case .sync: SyncView()
                case .shortClips: ShortClipsView()
                case .cacheClean: CacheCleanerView()
                case .appUninstall: AppUninstallerView()
                case .dupPhotos: DupPhotosView()
                case .videoDup: VideoDupView()
                case .videoMaker: VideoMakerView()
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
