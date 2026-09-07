import Foundation

/// 1本のOneDriveリンク(動画/写真)ぶんの「年/月フォルダ構造+選択状態」を保持する
/// 観測可能な状態オブジェクト。mygallery(Mac版)の`OneDriveFolderTreeViewController`
/// (`NSOutlineView`ベース)が持っていたのと同じ責務 ― フォルダ階層のインクリメンタル
/// 表示・チェック状態の親子伝播・選択の永続化 ― を、SwiftUIのグリッド/チップUI向けに
/// 単純化したモデルとして新規に書いたもの(iPad版で新しく必要になった、既存の
/// どちらの移植元にも無いファイル)。
///
/// 選択は`selectedPaths: Set<[String]>`で表す(`[]`はここでは使わない ― ルート自体は
/// 選択単位にしない)。`["2026"]`は年フォルダ全体、`["2026", "09"]`は月フォルダ単体を
/// 指す。「年フォルダのパスが選択集合に入っていれば、個別に月のパスが入っていなくても
/// その年の全月を選択済みとみなす」祖先優先ルールはmygallery Mac版の
/// `isEffectivelyChecked`と同じだが、初期状態(全選択)では年・月どちらのパスも
/// 明示的に選択集合へ入れておくため、月を個別に外す操作は常に正しく機能する
/// (mygallery Mac版の`addTopLevelFolder`が`allPaths(in:)`で自分自身+全子孫を
/// 選択集合へ入れているのと同じ考え方)。
@MainActor
final class LinkBrowseState: ObservableObject {
    let link: HardcodedLink

    /// 年ごとの月一覧(名前のみ、表示順に整列済み)。フェーズ1のストリームが届くたびに
    /// 追加される。まだ届いていない年はキーが存在しない。
    @Published private(set) var months: [String: [String]] = [:]
    /// フェーズ1(年/月フォルダ構造)を読み込み中かどうか。
    @Published private(set) var isLoadingStructure = false
    /// フェーズ1が完了(またはエラーで終了)したか。
    @Published private(set) var structureLoaded = false
    @Published private(set) var structureError: String?
    /// 選択中のパス。`["2026"]`(年)または`["2026", "09"]`(月)。
    @Published var selectedPaths: Set<[String]> = []

    /// 年フォルダのフォルダ参照(フェーズ2で使う`driveId`/`itemId`を持つ)。
    private var yearRefs: [String: OneDriveMediaClient.OneDriveFolderRef] = [:]

    init(link: HardcodedLink) {
        self.link = link
    }

    /// 初めてこのリンクの画面を開いたときにフェーズ1(フォルダ構造)を読み込む。
    /// mygallery(Mac版)の「タブを開いたら自動で読み込む」挙動と同じ ― 実データ
    /// (フェーズ2)はまだ取得しない、フォルダ名の一覧だけの軽いリクエスト。
    func loadStructureIfNeeded() {
        guard !structureLoaded, !isLoadingStructure else { return }
        isLoadingStructure = true
        structureError = nil
        let saved = Settings.folderSelections[link.id].map(Self.decode)

        Task {
            do {
                var discoveredYears: [String] = []
                let stream = OneDriveMediaClient.scanFolderStructureStream(
                    shareURL: link.url, onlyTopLevelFolders: Set(link.availableFolders))
                for try await (_, yearFolder) in stream {
                    yearRefs[yearFolder.name] = yearFolder
                    months[yearFolder.name] = yearFolder.children.map(\.name)
                        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    discoveredYears.append(yearFolder.name)

                    // 保存済みの選択がある場合(前回起動時に選んだフォルダの復元)だけ、
                    // ストリーム到着のたびに選択集合へ積む。保存が無い(=初回起動)場合は
                    // ここでは積まず、ループ完了後にまとめて決める(下記参照 ―
                    // 新UIでは選択直後に自動でフェーズ2スキャンが走るため、初回は
                    // 全年月ではなく直近の年だけを選んでおき、最初の自動スキャンが
                    // 重くなりすぎないようにする、`ContentView`/`LinkDetailView`参照)。
                    if let saved {
                        let yearPath = [yearFolder.name]
                        let monthPaths = yearFolder.children.map { [yearFolder.name, $0.name] }
                        let allPathsForYear = Set([yearPath] + monthPaths)
                        selectedPaths.formUnion(allPathsForYear.intersection(saved))
                    }
                }
                isLoadingStructure = false
                structureLoaded = true
                if saved != nil {
                    // 保存済みの選択が今回のフォルダ構成と一件も一致しなかった場合の
                    // フォールバック(フォルダ構成が変わった等) ― 全選択に戻す。
                    if selectedPaths.isEmpty {
                        selectAll()
                    }
                } else if let latestYear = discoveredYears.max(by: {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }) {
                    // 初回起動(保存済み選択が一切無い)は直近の年だけを既定選択にする
                    // ― 全年月を既定にすると、リンクを開いた瞬間の自動フェーズ2スキャン
                    // (`LinkDetailView`)が最初から全期間ぶんになってしまい重いため。
                    selectedPaths = [[latestYear]]
                    persist()
                } else {
                    selectAll()
                }
            } catch {
                isLoadingStructure = false
                structureLoaded = true
                structureError = error.localizedDescription
            }
        }
    }

    var years: [String] {
        months.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func monthsFor(_ year: String) -> [String] {
        months[year] ?? []
    }

    /// 年フォルダ全体が選択済み(=その年のすべての月が実質的に選択されている)かどうか。
    /// UIの年チップの塗りつぶし判定に使う。
    func isYearSelected(_ year: String) -> Bool {
        let monthNames = months[year] ?? []
        guard !monthNames.isEmpty else { return selectedPaths.contains([year]) }
        return monthNames.allSatisfy { isMonthSelected(year, $0) }
    }

    /// 月フォルダが実質的に選択されているか(年フォルダ自体が選択済みなら、その月も
    /// 選択済みとみなす祖先優先ルール)。
    func isMonthSelected(_ year: String, _ month: String) -> Bool {
        selectedPaths.contains([year]) || selectedPaths.contains([year, month])
    }

    /// 年チップをタップ ― その年の全月を一括で選択/解除する。
    func toggleYear(_ year: String) {
        let yearPath = [year]
        let monthPaths = (months[year] ?? []).map { [year, $0] }
        let allPathsForYear = Set([yearPath] + monthPaths)
        if isYearSelected(year) {
            selectedPaths.subtract(allPathsForYear)
        } else {
            selectedPaths.formUnion(allPathsForYear)
        }
        persist()
    }

    /// 月チップをタップ ― その月だけを選択/解除する。年全体が選択済み("年"パスのみが
    /// 選択集合に入っている状態)でこの月を外す場合、年パス自体を外して他の月の
    /// パスを個別に補ってから、この月だけ外す(祖先優先ルールにより「年を外した
    /// せいで他の月まで一緒に外れる」事故を防ぐ)。
    func toggleMonth(_ year: String, _ month: String) {
        let monthPath = [year, month]
        let yearPath = [year]
        if selectedPaths.contains(yearPath) {
            // 年全体選択の状態から個別の月を外す ― 年パスを展開してから対象の月だけ除く。
            selectedPaths.remove(yearPath)
            for m in months[year] ?? [] where m != month {
                selectedPaths.insert([year, m])
            }
        } else if selectedPaths.contains(monthPath) {
            selectedPaths.remove(monthPath)
        } else {
            selectedPaths.insert(monthPath)
        }
        persist()
    }

    func selectAll() {
        var all: Set<[String]> = []
        for year in months.keys {
            all.insert([year])
            for month in months[year] ?? [] { all.insert([year, month]) }
        }
        selectedPaths = all
        persist()
    }

    func selectNone() {
        selectedPaths = []
        persist()
    }

    /// 現在選択されている月フォルダ(実際にフェーズ2で取得する対象)の一覧。
    func selectedLeafFolders() -> [OneDriveMediaClient.OneDriveFolderRef] {
        var result: [OneDriveMediaClient.OneDriveFolderRef] = []
        for year in months.keys {
            guard let yearRef = yearRefs[year] else { continue }
            for monthRef in yearRef.children where isMonthSelected(year, monthRef.name) {
                result.append(monthRef)
            }
        }
        return result
    }

    private func persist() {
        var all = Settings.folderSelections
        all[link.id] = Self.encode(selectedPaths)
        Settings.folderSelections = all
    }

    private static func encode(_ paths: Set<[String]>) -> Set<String> {
        Set(paths.map { $0.joined(separator: "/") })
    }
    private static func decode(_ paths: Set<String>) -> Set<[String]> {
        Set(paths.map { $0.components(separatedBy: "/") })
    }
}
