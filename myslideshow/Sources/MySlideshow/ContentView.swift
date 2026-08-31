import SwiftUI

/// トップレベル。ホーム画面(リンクごとの年別フォルダ選択+スライドショー設定+開始ボタン、
/// すべて1画面)とスライドショー画面を`isShowingSlideshow`で切り替えるだけの薄いコンテナ。
///
/// **OneDriveリンクは`links`にハードコードした固定配列だけ**(2026-08-29、「リンクは
/// めったにかわらないので、ハードコードのままでいい。設定にも追加や削除できなくていい」
/// という要望への対応)。現在2件: 動画専用「動画」・写真専用「写真」
/// (`HardcodedLink.kindFilter`で絞る)。
///
/// **年別チェックボックスの選択肢もハードコードで、OneDriveのスキャンは一切しない**
/// (2026-08-29、「写真は2020から2026までチェックボックスを決め打ちにして。動画は
/// 2020から2021に。リンクからはとらない」という要望への対応)。**実際にOneDriveへ
/// 写真・動画を取得しに行くのは「スライドショー開始」を押した瞬間だけ**(同じ要望の
/// 「スライドショー開始ではじめて、リンクへ動画、写真を取得しに行く」の部分)。
/// これは何度かの変遷を経た設計 ― 直前までは起動時に両リンクを丸ごとスキャンして
/// 年フォルダを動的に検出していたが、深くネストしたライブラリではそのスキャン自体が
/// 重く、しかも「チェックボックスの選択肢が知りたいだけなのに実データを全部取りに
/// 行ってしまう」というミスマッチがあったため、選択肢はハードコードに倒し、実データの
/// 取得は本当に必要になる「開始」の瞬間まで遅延させることにした。
struct ContentView: View {
    /// アプリにハードコードされたOneDriveリンク。ユーザー本人から渡された固定リンクで、
    /// 今後もめったに変わらない想定のため、追加・削除UIは持たずここに直書きする。
    /// 年別チェックボックスの選択肢(`availableFolders`)もハードコード ― OneDriveから
    /// 動的に取得しない(上記クラスコメント参照)。
    private static let links: [HardcodedLink] = [
        HardcodedLink(
            name: "動画",
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
    @State private var playbackMode = Settings.playbackMode
    /// PIPモード専用の浮動パネルを管理する(2026-08-30追加)。`.pip`のときだけ使う ―
    /// `.windowed`/`.fullScreen`はこれまで通りメインウィンドウの中身を`SlideshowView`へ
    /// 差し替える(下記`start()`参照)。
    private let pipController = PIPWindowController()

    var body: some View {
        ZStack {
            if isShowingSlideshow {
                // `.windowed`はリサイズ可能な大きめウィンドウへ広げる必要があるため、
                // ホーム画面(下記、固定420×560)とはあえて別の`.frame`にしてある ―
                // SwiftUIはこの`.frame`の制約を見てメインウィンドウのリサイズ可否・
                // サイズ範囲を自動的に更新するので、明示的なAppKit操作は
                // `SlideshowView.applyWindowModeIfNeeded()`側の「大きめサイズへ広げる」
                // 一度きりの調整だけで済んでいる。
                SlideshowView(
                    items: mediaItems,
                    playbackMode: playbackMode,
                    timeLimitMinutes: timeLimitMinutes,
                    onExit: { isShowingSlideshow = false }
                )
                .frame(minWidth: 420, minHeight: 320)
            } else {
                HomeView(
                    links: Self.links,
                    selectedFolders: selectedFolders,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    photoDuration: $photoDuration,
                    shuffleEnabled: $shuffleEnabled,
                    timeLimitMinutes: $timeLimitMinutes,
                    playbackMode: $playbackMode,
                    onToggleFolder: toggleFolder,
                    onSetAllFolders: setAllFolders,
                    onStart: start
                )
                .frame(width: 420, height: 560)
            }
        }
        .onChange(of: photoDuration) { newValue in Settings.photoDurationSeconds = newValue }
        .onChange(of: shuffleEnabled) { newValue in Settings.shuffleEnabled = newValue }
        .onChange(of: timeLimitMinutes) { newValue in Settings.timeLimitMinutes = newValue }
        .onChange(of: playbackMode) { newValue in Settings.playbackMode = newValue }
        .onAppear { ensureSelectionDefaults() }
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
    /// 実際に取得しに行く(mytubeと同じ全階層走査+一時的ネットワークエラーの自動リトライ、
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
                    // 選んだ年だけを辿る(リンク全体をスキャンしてから絞り込むと、
                    // 選んでいない年のツリーにも無駄にアクセスして遅くなるため)。
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
                switch playbackMode {
                case .windowed, .fullScreen:
                    isShowingSlideshow = true
                case .pip:
                    // メインウィンドウはホーム画面のまま ― PIP専用パネルだけを開く
                    // (`Core/PIPWindowController.swift`参照)。
                    pipController.show(items: final, timeLimitMinutes: timeLimitMinutes, onExit: {})
                }
            }
        }
    }
}
