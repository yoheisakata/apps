import SwiftUI

/// トップレベル。mytube-ipadの`ContentView.swift`と同じ構造 ― `NavigationSplitView`の
/// サイドバーにOneDriveリンク(ビデオ/写真)の一覧、detailに選択中リンクのグリッド画面
/// (`Views/LinkDetailView.swift`)を表示するマスター・ディテール構成。以前の版
/// (`screen: .home / .grid`をトグルするブロッキングのホーム画面方式)から、
/// mytube-ipad風のサイドバー常設ナビゲーションへ全面的に作り直した ―
/// `CLAUDE.md`のアーキテクチャ節参照。
///
/// **OneDriveリンクは`links`にハードコードした固定配列だけ**(myslideshow-ipad/
/// mygallery(Mac版)と同じ方針、mytube-ipadと違いリンク追加・削除UIは持たない)。
/// リンクをサイドバーで選ぶと、そのリンクの年/月フォルダ構造(フェーズ1)を自動取得し、
/// 構造が揃った時点で既定選択(初回は直近の年だけ、`Core/LinkBrowseState.swift`参照)
/// ぶんのフェーズ2スキャンを自動で始める ― mytube-ipadの「リンクを選ぶと即座に
/// スキャンが始まる」immediacyと同じ体験。
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

    @StateObject private var videoState = LinkBrowseState(link: ContentView.links[0])
    @StateObject private var photoState = LinkBrowseState(link: ContentView.links[1])

    @State private var selectedLinkID: String?
    /// キーは`HardcodedLink.id`(=url)。リンクを切り替えても`ContentView`が保持し続ける
    /// ため、いったんスキャンしたリンクへ戻ったときに再スキャンせずキャッシュを表示できる
    /// (mytube-ipadの`sources: [String: RemoteSource]`と同じ設計)。
    @State private var galleryStates: [String: LinkGalleryState] = [:]
    @State private var photoDuration = Settings.photoDurationSeconds
    @State private var shuffleEnabled = Settings.shuffleEnabled
    @State private var sortOrder = Settings.sortOrder
    @State private var showSizeBadge = Settings.showSizeBadge
    @State private var showDateBadge = Settings.showDateBadge
    /// サイドバーの年フィルター行(下記`yearFilterRows(for:)`)を各リンクごとに
    /// 開閉するための状態。既定で両リンクとも展開しておく(2026-09-07追加の機能を
    /// すぐ目に入るようにするため)。
    @State private var expandedLinkIDs: Set<String> = Set(ContentView.links.map(\.id))

    private var browseStates: [LinkBrowseState] { [videoState, photoState] }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedLinkID) {
                ForEach(Self.links) { link in
                    DisclosureGroup(isExpanded: expandedBinding(for: link)) {
                        yearFilterRows(for: link)
                    } label: {
                        Text(link.name)
                            .font(.caption)
                            .tag(link.id)
                    }
                }
            }
            .navigationTitle("MyGallery Pad")
            // mytube-ipadの`ContentView`と同じ固定幅(全角4文字程度が収まる幅)。
            // 年フィルター行が増えた分、少しだけ広げてある。
            .navigationSplitViewColumnWidth(170)
            .task {
                // サイドバーの年フィルターは「そのリンクを一度開いた後」でなくても
                // 使えるようにしたいため、両リンクぶんのフォルダ構造(フェーズ1)を
                // ここで先読みしておく(`LinkDetailView`の`.task(id:)`と同じ呼び出しだが
                // `loadStructureIfNeeded()`は多重実行安全なガード付きなので重複しても害はない)。
                videoState.loadStructureIfNeeded()
                photoState.loadStructureIfNeeded()
            }
        } detail: {
            if let link = Self.links.first(where: { $0.id == selectedLinkID }) {
                LinkDetailView(
                    link: link,
                    browseState: browseState(for: link),
                    gallery: galleryStates[link.id] ?? LinkGalleryState(),
                    photoDuration: $photoDuration,
                    shuffleEnabled: $shuffleEnabled,
                    sortOrder: $sortOrder,
                    showSizeBadge: $showSizeBadge,
                    showDateBadge: $showDateBadge,
                    onScan: { await scan(link: link) }
                )
                .id(link.id)
            } else {
                ContentUnavailableView(
                    "リンクを選んでください",
                    systemImage: "sidebar.left",
                    description: Text("左のリストからOneDriveの共有リンクを選ぶと写真・動画一覧が表示されます")
                )
            }
        }
        .onChange(of: photoDuration) { _, newValue in Settings.photoDurationSeconds = newValue }
        .onChange(of: shuffleEnabled) { _, newValue in Settings.shuffleEnabled = newValue }
        .onChange(of: showSizeBadge) { _, newValue in Settings.showSizeBadge = newValue }
        .onChange(of: showDateBadge) { _, newValue in Settings.showDateBadge = newValue }
        .onChange(of: sortOrder) { _, newValue in
            Settings.sortOrder = newValue
            // 並び替え順の変更はOneDriveへ取り直しに行かず、既に取得済みの
            // アイテムをその場で並べ替えるだけにする(Mac版のツールバー並び替えと
            // 同じ体感 ― 選ぶたびに毎回重いフェーズ2スキャンが走ると使いづらいため)。
            for key in galleryStates.keys {
                galleryStates[key]?.items = newValue.sorted(galleryStates[key]?.items ?? [])
            }
        }
    }

    private func browseState(for link: HardcodedLink) -> LinkBrowseState {
        browseStates.first(where: { $0.link.id == link.id }) ?? videoState
    }

    private func expandedBinding(for link: HardcodedLink) -> Binding<Bool> {
        Binding(
            get: { expandedLinkIDs.contains(link.id) },
            set: { isExpanded in
                if isExpanded { expandedLinkIDs.insert(link.id) } else { expandedLinkIDs.remove(link.id) }
            }
        )
    }

    /// サイドバーの年フィルター行(2026-09-07追加)。mygallery(Mac版)の
    /// `OneDriveFolderTreeViewController`(Year/Monthのチェックボックスツリー)の
    /// うち、**年レベルの選択だけ**をサイドバーへ持ってきたもの ― 月レベルの
    /// 絞り込みは従来通り`Views/FolderPickerSheet.swift`(ツールバーの「年/月を
    /// 選ぶ」)に残してある。両方とも同じ`LinkBrowseState.selectedPaths`を直接
    /// 操作するので、サイドバーとシートのどちらで変更しても状態は食い違わない。
    ///
    /// **設計判断: シートは廃止せず併存させた。** 年だけならサイドバーの一覧性・
    /// 即応性(タップしてすぐ絞り込める)が勝るが、月単位の細かい絞り込みまで
    /// サイドバーへ詰め込むとネストが深くなり`NavigationSplitView`のサイドバー
    /// 幅では窮屈になる(実機の狭い幅を想定)。シートには元々スライドショー設定
    /// (ランダム再生・写真の表示時間)も同居しているため、「年はサイドバーで
    /// ざっくり」「月・その他の設定はシートでじっくり」という役割分担にした。
    private func yearFilterRows(for link: HardcodedLink) -> some View {
        let state = browseState(for: link)
        return ForEach(state.years, id: \.self) { year in
            Button {
                state.toggleYear(year)
                Task { await scan(link: link) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.isYearSelected(year) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(state.isYearSelected(year) ? Color.accentColor : .secondary)
                    Text(year)
                    Spacer()
                }
                .font(.caption2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 選択中の年/月フォルダに該当する葉フォルダだけをOneDriveへ実際に取得しに行く
    /// (フェーズ2、`OneDriveMediaClient.scanLeafFolders`)。以前の版(`ContentView
    /// .openGrid`)は両リンクぶんをまとめて1つの`mediaItems`配列にしていたが、
    /// このリンク単体のグリッド画面用に、リンクごとの結果を`galleryStates`へ
    /// 個別に保存する形へ変更した。
    ///
    /// **不具合修正(2026-09-07): プルダウン更新でグリッドが空になる問題。**
    /// 以前は「選択中の葉フォルダが1つも無い」場合に`current.items = []`で
    /// 無条件に上書きしていた。単体では見えにくいが、フォルダピッカーの
    /// `onDismiss`と`.refreshable`のプルダウンはどちらも同じ`onScan`(=この関数)を
    /// 叩くため、狭い時間差で2回の`scan()`が並行実行されるケースがある ―
    /// 例えば「フォルダピッカーを閉じた直後にもう一度素早く引っぱって更新する」と、
    /// 先に始まった呼び出し(古い選択状態を見ている)が、後から始まって先に完了した
    /// 呼び出し(新しい選択状態の結果)を後から上書きしてしまう。`isLoading`だけを
    /// 見た再入防止では、既に完了した呼び出しどうしの「後勝ち」の順序までは
    /// 保証できない。そこで`LinkGalleryState.generation`という単調カウンタを導入し、
    /// 各`scan()`呼び出しが自分の開始時点の世代番号を持ち歩き、結果を書き込む直前に
    /// 「自分が最新の呼び出しか」を確認するようにした(`applyResult`)。
    ///
    /// 加えて、指示された通り「見つかった葉フォルダが0件」「取得した結果が0件」
    /// どちらの場合も、**既にグリッドに表示中のアイテムがあるときはそれを消さない**
    /// ように変更した ― 一時的な取得ゼロ件(またはユーザーがフォルダピッカーで
    /// 一旦全解除しただけ等)でグリッドが真っ白になる体験を避けるため。空/エラー
    /// メッセージは「元々何も表示されていなかった」ときだけ出す。
    private func scan(link: HardcodedLink) async {
        let key = link.id
        guard galleryStates[key]?.isLoading != true else { return }
        var current = galleryStates[key] ?? LinkGalleryState()
        current.generation += 1
        let myGeneration = current.generation
        current.isLoading = true
        current.errorMessage = nil
        current.hasScannedOnce = true
        galleryStates[key] = current

        let state = browseState(for: link)
        let leaves = state.selectedLeafFolders()
        guard !leaves.isEmpty else {
            applyResult(key: key, generation: myGeneration) { c in
                c.isLoading = false
                // 選択フォルダが0件でも、既に表示中のアイテムはそのまま残す。
                // 本当に「一度も何も表示されていない」場合だけ空表示にする。
            }
            return
        }

        do {
            var collected: [MediaItem] = []
            let stream = OneDriveMediaClient.scanLeafFolders(shareURL: state.link.url, folders: leaves)
            for try await (_, folderItems) in stream {
                collected += folderItems
            }
            if let kindFilter = state.link.kindFilter {
                collected = collected.filter { $0.kind == kindFilter }
            }
            collected = SortOrder.current.sorted(collected)
            Log.scan.notice("scan(\(link.name, privacy: .public)): 件数=\(collected.count)")
            applyResult(key: key, generation: myGeneration) { c in
                c.isLoading = false
                // 取得結果が0件でも、既に表示中のアイテムがあれば消さない(下記コメント参照)。
                if !collected.isEmpty || c.items.isEmpty {
                    c.items = collected
                }
            }
        } catch {
            Log.scan.error("scan(\(link.name, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
            applyResult(key: key, generation: myGeneration) { c in
                c.isLoading = false
                // 失敗時も既存のアイテムは残す ― エラーメッセージは元々何も
                // 表示されていなかったときの補助情報としてのみ使う。
                if c.items.isEmpty {
                    c.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// `scan(link:)`の結果を`galleryStates`へ書き戻す共通ヘルパー。書き込み直前に
    /// この呼び出しがまだ最新の世代(`generation`)であることを確認し、既により新しい
    /// `scan()`呼び出しが結果を書き込んでいた場合は何もしない(上記コメント参照)。
    private func applyResult(key: String, generation: Int, _ mutate: (inout LinkGalleryState) -> Void) {
        guard var current = galleryStates[key], current.generation == generation else { return }
        mutate(&current)
        galleryStates[key] = current
    }
}
