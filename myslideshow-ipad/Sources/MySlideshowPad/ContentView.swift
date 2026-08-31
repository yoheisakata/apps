import SwiftUI

/// トップレベル。ホーム画面(リンクごとの年別フォルダ選択+スライドショー設定+開始ボタン、
/// すべて1画面)とスライドショー画面を`isShowingSlideshow`で切り替えるだけの薄いコンテナ。
/// myslideshow(Mac版)の同名ファイルから移植 ― **`playbackMode`(ウィンドウ内/全画面/PIP)は
/// 移植していない**。iPadはWindowGroupが常にフルスクリーンで開くため、Mac版のような
/// ウィンドウサイズの出し分け・PIP用の別パネルという概念自体が無い(下記`CLAUDE.md`参照)。
///
/// **OneDriveリンクは`links`にハードコードした固定配列だけ**(Mac版と同じ方針 ―
/// 「リンクはめったにかわらないので、ハードコードのままでいい」)。年別チェックボックスの
/// 選択肢もハードコードで、OneDriveのスキャンは一切しない。実際にOneDriveへ写真・動画を
/// 取得しに行くのは「スライドショー開始」を押した瞬間だけ。
struct ContentView: View {
    /// アプリにハードコードされたOneDriveリンク。Mac版の`ContentView.links`と同じ値 ―
    /// リンク・年の範囲を変える場合はこの配列を直接編集する。
    private static let links: [HardcodedLink] = [
        HardcodedLink(
            name: "動画",
            url: "https://1drv.ms/f/c/6b83b2b7da86a08f/IgCnAW6bjrzaQ5MFMH8h-w3oAbOsSLkLLLzMzHoMxn_CWzo?e=YS9SKE",
            kindFilter: .video,
            availableFolders: ["2020", "2021"]
        ),
        HardcodedLink(
            name: "写真",
            url: "https://1drv.ms/f/c/22558ab42b6166a7/IgCnZmErtIpVIIAi9kQGAAAAATumoVsXYR__s2VdsQrfg00?e=VCUJRX",
            kindFilter: .photo,
            availableFolders: ["2020", "2021", "2022", "2023", "2024", "2025", "2026"]
        ),
    ]

    /// キーは`HardcodedLink.id`(＝URL文字列)。チェックボックスの選択状態だけを持つ
    /// (スキャン結果は持たない ― 「開始」時に毎回取得し直すため)。
    @State private var selectedFolders: [String: Set<String>] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var mediaItems: [MediaItem] = []
    @State private var isShowingSlideshow = false
    @State private var photoDuration = Settings.photoDurationSeconds
    @State private var shuffleEnabled = Settings.shuffleEnabled
    @State private var timeLimitMinutes = Settings.timeLimitMinutes

    var body: some View {
        ZStack {
            if isShowingSlideshow {
                SlideshowView(
                    items: mediaItems,
                    timeLimitMinutes: timeLimitMinutes,
                    onExit: { isShowingSlideshow = false }
                )
            } else {
                HomeView(
                    links: Self.links,
                    selectedFolders: selectedFolders,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    photoDuration: $photoDuration,
                    shuffleEnabled: $shuffleEnabled,
                    timeLimitMinutes: $timeLimitMinutes,
                    onToggleFolder: toggleFolder,
                    onSetAllFolders: setAllFolders,
                    onStart: start
                )
            }
        }
        .onChange(of: photoDuration) { _, newValue in Settings.photoDurationSeconds = newValue }
        .onChange(of: shuffleEnabled) { _, newValue in Settings.shuffleEnabled = newValue }
        .onChange(of: timeLimitMinutes) { _, newValue in Settings.timeLimitMinutes = newValue }
        .onAppear { ensureSelectionDefaults() }
        .statusBarHidden(isShowingSlideshow)
    }

    /// チェックボックスの初期選択(ハードコードした`availableFolders`全部)を、保存済みの
    /// 選択(`Settings.folderSelections`)があればそれで上書きする。OneDriveへは一切
    /// アクセスしない(選択肢自体がハードコードのため)。
    private func ensureSelectionDefaults() {
        for link in Self.links where selectedFolders[link.id] == nil {
            let available = Set(link.availableFolders)
            let saved = Settings.folderSelections[link.id]?.intersection(available)
            selectedFolders[link.id] = (saved?.isEmpty == false) ? saved! : available
        }
    }

    private func toggleFolder(_ link: HardcodedLink, _ folder: String) {
        var current = selectedFolders[link.id] ?? Set(link.availableFolders)
        if current.contains(folder) {
            current.remove(folder)
        } else {
            current.insert(folder)
        }
        selectedFolders[link.id] = current
        Settings.folderSelections[link.id] = current
    }

    /// 「全選択」/「全非選択」ボタン(`Views/HomeView.swift`)用。
    private func setAllFolders(_ link: HardcodedLink, selected: Bool) {
        let value = selected ? Set(link.availableFolders) : []
        selectedFolders[link.id] = value
        Settings.folderSelections[link.id] = value
    }

    /// 「スライドショー開始」が押された瞬間に、選んだ年に該当するリンクだけOneDriveへ
    /// 実際に取得しに行く(Mac版と同じ全階層走査+一時的ネットワークエラーの自動リトライ、
    /// `OneDriveMediaClient.scanWithRetry`)。
    private func start() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            var final: [MediaItem] = []
            var failureMessages: [String] = []
            for link in Self.links {
                let folders = selectedFolders[link.id] ?? Set(link.availableFolders)
                guard !folders.isEmpty else { continue }
                do {
                    let result = try await OneDriveMediaClient.scanWithRetry(shareURL: link.url, onlyTopLevelFolders: folders)
                    var items = result.items
                    if let kindFilter = link.kindFilter {
                        items = items.filter { $0.kind == kindFilter }
                    }
                    items.sort { a, b in
                        let ap = a.folderPath.joined(separator: "/")
                        let bp = b.folderPath.joined(separator: "/")
                        if ap != bp { return ap < bp }
                        return a.name.localizedStandardCompare(b.name) == .orderedAscending
                    }
                    Log.scan.notice("start(\(link.name, privacy: .public)): 全件=\(result.items.count) 絞込後=\(items.count)")
                    final += items
                } catch {
                    Log.scan.error("start(\(link.name, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
                    failureMessages.append("\(link.name): \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                isLoading = false
                guard !final.isEmpty else {
                    errorMessage = failureMessages.isEmpty
                        ? "写真・動画が見つかりませんでした"
                        : failureMessages.joined(separator: "\n")
                    return
                }
                if shuffleEnabled { final.shuffle() }
                mediaItems = final
                isShowingSlideshow = true
            }
        }
    }
}
