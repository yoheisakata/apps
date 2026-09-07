import SwiftUI
import os

/// トップレベル。ホーム画面(年/月フォルダ選択+スライドショー設定)とグリッド画面を
/// `screen`で切り替える薄いコンテナ。myslideshow-ipadの同名ファイルがベース(ホーム画面
/// の状態管理・「開始」時に選択済みフォルダだけをOneDriveへ取得しに行く設計)だが、
/// **「開始」の遷移先がスライドショーではなくグリッド画面になっている**のが最大の違い
/// (`CLAUDE.md`のアーキテクチャ節参照 ― グリッド画面からさらにビューア/スライドショーへ
/// 進める)。
///
/// **OneDriveリンクは`links`にハードコードした固定配列だけ**(myslideshow-ipad/
/// mygallery(Mac版)と同じ方針)。年別フォルダの選択肢もハードコードだが、月フォルダの
/// 一覧自体はホーム画面が開いたタイミングで軽量なフェーズ1(`OneDriveMediaClient
/// .scanFolderStructureStream`)を自動で取得する(mygallery Mac版の「タブを開いたら
/// 自動で読み込む」挙動と同じ)。実際の写真・動画(フェーズ2)を取得しに行くのは
/// 「グリッドを開く」を押した瞬間だけ。
struct ContentView: View {
    private static let links: [HardcodedLink] = [
        HardcodedLink(
            name: "ビデオ",
            url: "https://1drv.ms/f/c/6b83b2b7da86a08f/IgCnAW6bjrzaQ5MFMH8h-w3oAbOsSLkLLLzMzHoMxn_CWzo?e=YS9SKE",
            kindFilter: .video,
            availableFolders: ["2020", "2021", "2022", "2023", "2024", "2025", "2026"]
        ),
        HardcodedLink(
            name: "写真",
            url: "https://1drv.ms/f/c/22558ab42b6166a7/IgCnZmErtIpVIIAi9kQGAAAAATumoVsXYR__s2VdsQrfg00?e=VCUJRX",
            kindFilter: .photo,
            availableFolders: ["2020", "2021", "2022", "2023", "2024", "2025", "2026"]
        ),
    ]

    private enum Screen {
        case home
        case grid
    }

    @StateObject private var videoState = LinkBrowseState(link: ContentView.links[0])
    @StateObject private var photoState = LinkBrowseState(link: ContentView.links[1])

    @State private var screen: Screen = .home
    @State private var isLoadingItems = false
    @State private var errorMessage: String?
    @State private var mediaItems: [MediaItem] = []
    @State private var photoDuration = Settings.photoDurationSeconds
    @State private var shuffleEnabled = Settings.shuffleEnabled

    private var states: [LinkBrowseState] { [videoState, photoState] }

    var body: some View {
        ZStack {
            switch screen {
            case .home:
                HomeView(
                    states: states,
                    isLoadingItems: isLoadingItems,
                    errorMessage: errorMessage,
                    photoDuration: $photoDuration,
                    shuffleEnabled: $shuffleEnabled,
                    onOpen: openGrid
                )
            case .grid:
                GridView(
                    items: mediaItems,
                    onBack: { screen = .home },
                    onReload: openGrid,
                    shuffleEnabled: shuffleEnabled
                )
            }
        }
        .onChange(of: photoDuration) { _, newValue in Settings.photoDurationSeconds = newValue }
        .onChange(of: shuffleEnabled) { _, newValue in Settings.shuffleEnabled = newValue }
    }

    /// 「グリッドを開く」が押された瞬間に、選んだ年/月フォルダに該当する葉フォルダだけ
    /// OneDriveへ実際に取得しに行く(フェーズ2、`OneDriveMediaClient.scanLeafFolders`)。
    /// 両方のリンク(ビデオ/写真)ぶんをまとめて1つの`mediaItems`配列にし、グリッドへ渡す。
    private func openGrid() {
        guard !isLoadingItems else { return }
        isLoadingItems = true
        errorMessage = nil
        Task {
            var final: [MediaItem] = []
            var failureMessages: [String] = []
            for state in states {
                let leaves = state.selectedLeafFolders()
                guard !leaves.isEmpty else { continue }
                do {
                    var items: [MediaItem] = []
                    let stream = OneDriveMediaClient.scanLeafFolders(shareURL: state.link.url, folders: leaves)
                    for try await (_, folderItems) in stream {
                        items += folderItems
                    }
                    if let kindFilter = state.link.kindFilter {
                        items = items.filter { $0.kind == kindFilter }
                    }
                    Log.scan.notice("openGrid(\(state.link.name, privacy: .public)): 件数=\(items.count)")
                    final += items
                } catch {
                    Log.scan.error("openGrid(\(state.link.name, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
                    failureMessages.append("\(state.link.name): \(error.localizedDescription)")
                }
            }
            final.sort { a, b in
                let ap = a.folderPath.joined(separator: "/")
                let bp = b.folderPath.joined(separator: "/")
                if ap != bp { return ap > bp }
                return a.name.localizedStandardCompare(b.name) == .orderedDescending
            }
            await MainActor.run {
                isLoadingItems = false
                guard !final.isEmpty else {
                    errorMessage = failureMessages.isEmpty
                        ? "写真・動画が見つかりませんでした"
                        : failureMessages.joined(separator: "\n")
                    return
                }
                mediaItems = final
                screen = .grid
            }
        }
    }
}
