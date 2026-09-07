import AppKit

/// 単一カラムの`NSOutlineView`で、カラム幅を実際の表示幅に追従させる。デフォルトの
/// `columnAutoresizingStyle`(`.lastColumnOnlyAutoresizingStyle`)は「テーブル自身の
/// フレーム変更イベント」に追従して差分を配分する方式で、サイドバーの実サイズが
/// 確定するタイミング次第では反映されないことがある ― カラム幅が古い(狭い)まま
/// 残ると、セルの`NSTextField`は実際のサイドバー幅よりずっと狭い領域に押し込まれ、
/// `lineBreakMode`のせいで余白がたっぷり残っているのに文字だけ「…」で途切って見える
/// (2026-09-06、OneDriveの年/月フォルダツリーで実機確認して発覚)。レイアウトのたびに
/// 明示的にカラム幅を同期させることで確実に追従させる。ローカル/OneDriveどちらの
/// サイドバーも同じ`NSOutlineView`パターンなので、両方から使う共通ヘルパーにしてある。
extension NSOutlineView {
    func syncSingleColumnWidthToBounds() {
        guard let col = tableColumns.first else { return }
        let width = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        if width > 0, abs(col.width - width) > 0.5 {
            col.width = width
        }
    }
}

// OneDrive 共有リンクのブラウズ UI。2026-09-06以前はリンクをUIから自由に追加・削除できる
// 汎用ギャラリー向けの作りだったが、実際には動画用・写真用の2つの決め打ちリンクしか
// 使っていなかったため、ユーザー要望でMySlideshow時代と同じ「決め打ち2リンク、
// サイドバーはローカル/動画/画像の3タブ」に戻した(リンク追加・削除UIは廃止)。

// MARK: - Settings (UserDefaults)

/// OneDrive関連の設定の一元管理(myslideshowの`Core/Settings.swift`と同じ方針)。
enum GallerySettings {
    private static let folderTreeSelectionsKey = "mygallery.oneDriveFolderTreeSelections"
    private static let slideshowPhotoDurationKey = "mygallery.slideshowPhotoDurationSeconds"
    private static let slideshowShuffleKey = "mygallery.slideshowShuffleEnabled"
    private static let slideshowTimeLimitKey = "mygallery.slideshowTimeLimitMinutes"
    private static let slideshowAutoFullscreenKey = "mygallery.slideshowAutoFullscreen"

    /// リンクごと(`OneDriveLink.id`がキー)に、年/月フォルダツリーで最後にチェックして
    /// いたフォルダの集合。パスは`/`区切りの文字列にして保存する(ルート自身は空文字列)。
    /// 「動画(OD)/画像(OD)タブを開いたら前回選んでいたものを自動で復元する」ための状態で、
    /// 未保存(キー無し)は「全フォルダ表示」を意味する。
    static var folderTreeSelections: [String: Set<String>] {
        get {
            guard let data = UserDefaults.standard.data(forKey: folderTreeSelectionsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Set<String>].self, from: data)) ?? [:]
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: folderTreeSelectionsKey)
        }
    }

    static var slideshowPhotoDurationSeconds: Double {
        get {
            let v = UserDefaults.standard.double(forKey: slideshowPhotoDurationKey)
            return v > 0 ? v : 6.0
        }
        set { UserDefaults.standard.set(newValue, forKey: slideshowPhotoDurationKey) }
    }

    static var slideshowShuffleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: slideshowShuffleKey) }
        set { UserDefaults.standard.set(newValue, forKey: slideshowShuffleKey) }
    }

    /// 分単位、5分刻み。`nil`は無制限。
    static var slideshowTimeLimitMinutes: Int? {
        get {
            let v = UserDefaults.standard.integer(forKey: slideshowTimeLimitKey)
            return v > 0 ? v : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: slideshowTimeLimitKey) }
    }

    static var slideshowAutoFullscreen: Bool {
        get {
            UserDefaults.standard.object(forKey: slideshowAutoFullscreenKey) == nil
                ? true   // 既定はオン(MySlideshowの唯一の従来挙動を踏襲)
                : UserDefaults.standard.bool(forKey: slideshowAutoFullscreenKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: slideshowAutoFullscreenKey) }
    }
}

// MARK: - Model

/// OneDriveの共有リンク1つ分の設定。2026-09-06以前はUIから追加・削除できる汎用データ
/// だったが、決め打ち2リンク運用に戻したので、今は下の`OneDriveLinks.video`/`.photo`と
/// いう固定値としてのみ存在する(`Codable`は不要になったので外した)。
struct OneDriveLink: Identifiable, Equatable {
    var id: String { url }
    var name: String
    var url: String
    /// 対象を絞る場合のメディア種別(nilなら写真・動画どちらも対象)。
    var kindFilter: MediaKind?
    /// スキャン対象のトップレベル(年)フォルダ一覧 ― ネットワークスキャンの範囲を絞るため
    /// のもの(`OneDriveMediaClient.swift`冒頭のコメント参照)。決め打ち運用なので毎回
    /// この全件をスキャン対象にする(以前あった「読み込み前にユーザーが選ぶ」UIは廃止した)。
    var availableFolders: [String]
}

/// MySlideshow(廃止済み)から引き継いだ、決め打ちの2リンク。
enum OneDriveLinks {
    static let video = OneDriveLink(
        name: "ビデオ",
        url: "https://1drv.ms/f/c/6b83b2b7da86a08f/IgCnAW6bjrzaQ5MFMH8h-w3oAbOsSLkLLLzMzHoMxn_CWzo?e=YS9SKE",
        kindFilter: .video,
        availableFolders: ["2020", "2021", "2022", "2023", "2024", "2025", "2026"]
    )
    static let photo = OneDriveLink(
        name: "写真",
        url: "https://1drv.ms/f/c/22558ab42b6166a7/IgCnZmErtIpVIIAi9kQGAAAAATumoVsXYR__s2VdsQrfg00?e=VCUJRX",
        kindFilter: .photo,
        availableFolders: ["2020", "2021", "2022", "2023", "2024", "2025", "2026"]
    )
}

// MARK: - Folder tree (年/月フォルダで絞り込んで表示する画面。動画(OD)/画像(OD)タブの中身そのもの)

/// 読み込んだOneDriveリンクの実際のフォルダ階層(年/月、`OneDriveMediaClient
/// .OneDriveFolderRef`由来)の1ノード。ローカルの`FolderNode`と同じ役割だが、
/// OneDriveアイテムはURLではなくパスコンポーネントでフォルダ階層を表すため、
/// こちらは`[String]`ベースにしている。
final class OneDriveFolderNode: NSObject {
    let name: String
    /// ルートから見たパスコンポーネント(例: ["2026", "09"])。ルート自身は`[]`。
    let pathComponents: [String]
    /// フェーズ2(`scanLeafFolders`)でこのフォルダの中身を取得する際に必要。
    /// ルートノードには実体が無いので`nil`。
    let driveId: String?
    let itemId: String?
    weak var parent: OneDriveFolderNode?
    var children: [OneDriveFolderNode] = []
    /// 子を持たない(=実際の写真・動画が入っている月フォルダ相当)かどうか。
    var isLeaf: Bool { children.isEmpty }
    /// フェーズ2でこのフォルダの中身を取得し終えたか。葉フォルダにのみ意味を持つ。
    var itemsLoaded = false
    /// 件数。葉フォルダは`itemsLoaded`になった時点で実数が入り、それより上位の
    /// フォルダ・ルートは配下の葉の合計(未取得の葉は0として扱う ― 読み込みが
    /// 進むにつれて表示上の数字が増えていく)。

    var totalCount = 0

    init(name: String, pathComponents: [String], driveId: String?, itemId: String?, parent: OneDriveFolderNode?) {
        self.name = name
        self.pathComponents = pathComponents
        self.driveId = driveId
        self.itemId = itemId
        self.parent = parent
    }

    /// この配下(自分自身含む)の葉ノードを再帰的に集める。
    func allLeaves() -> [OneDriveFolderNode] {
        if isLeaf { return [self] }
        return children.flatMap { $0.allLeaves() }
    }
}

/// 動画(OD)/画像(OD)タブの中身。年/月フォルダのチェックボックスツリーで絞り込んで表示する
/// (ローカルの`SidebarViewController`と同じUX ― チェックは表示するフォルダを絞り込むだけで、
/// 追加のネットワークアクセスは発生しない。全件はすでに読み込み済みの`PhotoItem`配列にある)。
/// 決め打ちの`link`を1つだけ受け持つ ― 以前あった「リンクを選ぶ」画面は廃止したので、
/// このビューコントローラー自体がそのままタブの中身になる。
final class OneDriveFolderTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let link: OneDriveLink
    private let outline = NSOutlineView()
    private let cellID = NSUserInterfaceItemIdentifier("OneDriveFolderTreeCell")
    private let statusLabel = NSTextField(labelWithString: "")

    private(set) var rootNode: OneDriveFolderNode?
    private(set) var checkedPaths: Set<[String]> = []
    /// パスコンポーネント→ノードの索引。フェーズ2の結果(どのフォルダから何件届いたか)を
    /// 該当ノードに反映する際、木を毎回辿らずに引けるようにする。
    private var nodesByPath: [[String]: OneDriveFolderNode] = [:]

    /// チェック状態(=表示に含めるフォルダ)が変わるたびに呼ばれる。
    var onCheckedChanged: (() -> Void)?

    init(link: OneDriveLink) {
        self.link = link
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 8, right: 8)
        container.frame = NSRect(x: 0, y: 0, width: 220, height: 600)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("onedrivefolders"))
        col.isEditable = false
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.allowsEmptySelection = true
        outline.selectionHighlightStyle = .none   // 選択ではなくチェックボックスで絞り込む(ローカルと同じ)
        outline.dataSource = self
        outline.delegate = self
        outline.autoresizesOutlineColumn = true
        scroll.documentView = outline
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        container.addArrangedSubview(statusLabel)
        container.addArrangedSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // 垂直`NSStackView`はデフォルトの`alignment`(`.centerX`)だとアレンジ済み
        // サブビューをスタックの幅いっぱいに広げてくれず、内容(ここでは`NSOutlineView`)の
        // 持つ幅なりのサイズに縮こまる。`scroll`の幅を明示的に`container`と揃えないと、
        // `outline`の列幅は結局「自分の現在の幅」を元に計算する
        // `syncSingleColumnWidthToBounds()`と堂々巡りになり、サイドバーが実際にはもっと
        // 広いのに列幅だけ古い(狭い)ままになってしまう(2026-09-06、実機で確認して発覚 ―
        // フォルダ名の右に空白が残っているのに文字だけ途切れて見えた原因)。
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        outline.syncSingleColumnWidthToBounds()
    }

    func setStatus(_ text: String) { statusLabel.stringValue = text }

    /// `beginIncrementalLoad`で一度だけ決め、年フォルダが1つ届くたびに`addTopLevelFolder`が
    /// 参照する「その年フォルダぶんをどうチェック状態にするか」の方針。全部の年フォルダが
    /// 揃うまで待たずに絞り込み状態を復元するため、年フォルダごとに随時判定する。
    private enum PendingSelection {
        case selectAll
        case restore(Set<[String]>)
    }
    private var pendingSelection: PendingSelection = .selectAll

    /// 読み込み開始時に呼ぶ。空のルートノードだけを作ってすぐサイドバーに反映し
    /// (「フォルダを確認中…」のまま何も出ない状態を避ける)、以降は
    /// `addTopLevelFolder(_:)`を年フォルダが解決するたびに呼んでツリーへ随時追加していく
    /// ― 「レイヤーごとに徐々に表示してほしい」というユーザー要望への対応(2026-09-06)。
    func beginIncrementalLoad(rootName: String) {
        let root = OneDriveFolderNode(name: rootName, pathComponents: [], driveId: nil, itemId: nil, parent: nil)
        rootNode = root
        nodesByPath = [[]: root]
        checkedPaths = []
        if let saved = GallerySettings.folderTreeSelections[link.id] {
            pendingSelection = .restore(Self.decode(saved))
        } else {
            pendingSelection = .selectAll
        }
        outline.reloadData()
        outline.expandItem(root)
    }

    /// フェーズ1の年フォルダ1つぶんが解決するたびに呼ぶ。ルート直下へ追加し、名前順で
    /// 並び直してから再描画する。チェック状態は、保存済みの選択があればこの年フォルダの
    /// パスのうち含まれるものだけ、無ければ(=既定は全選択)この年フォルダのパスを
    /// すべてチェック済みにする ― 全年フォルダが揃うのを待たずに絞り込みを反映する。
    func addTopLevelFolder(_ ref: OneDriveMediaClient.OneDriveFolderRef) {
        guard let root = rootNode else { return }
        func convert(_ ref: OneDriveMediaClient.OneDriveFolderRef, parent: OneDriveFolderNode) -> OneDriveFolderNode {
            let node = OneDriveFolderNode(name: ref.name, pathComponents: ref.pathComponents,
                                           driveId: ref.driveId, itemId: ref.itemId, parent: parent)
            node.children = ref.children.map { convert($0, parent: node) }
            return node
        }
        let node = convert(ref, parent: root)
        root.children.append(node)
        root.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        func index(_ n: OneDriveFolderNode) {
            nodesByPath[n.pathComponents] = n
            n.children.forEach(index)
        }
        index(node)

        let paths = allPaths(in: node)
        switch pendingSelection {
        case .restore(let saved):
            checkedPaths.formUnion(paths.intersection(saved))
        case .selectAll:
            checkedPaths.formUnion(paths)
        }

        outline.reloadData()
        outline.expandItem(root)
        // 年フォルダ(Month群を子に持つノード)自体は展開しない ― 起動直後は
        // Year一覧だけ見せて、Monthはユーザーが開くまでたたんでおく
        // (2026-09-07、ユーザー要望「起動時、MonthフォルダはCollapseしておいて」
        // への対応。以前は届いた年フォルダを自動展開していたので、年フォルダが
        // 多いと開いた瞬間からMonthまでずらっと展開された長い一覧になっていた)。
    }

    /// フェーズ1の全年フォルダが届き終わったら呼ぶ。保存済みの選択が今回のツリーに
    /// 一件も一致しなかった(フォルダ構成が変わった等)場合のフォールバックとして、
    /// 空のままなら全選択に戻す ― 従来の`setRoot`にあった安全策と同じ。
    func finishIncrementalLoad() {
        guard let root = rootNode else { return }
        if checkedPaths.isEmpty { checkedPaths = allPaths(in: root) }
        outline.reloadData()
    }

    /// 現在チェックされている葉フォルダ(実際に写真・動画が入っているフォルダ)の一覧。
    /// フェーズ2(`MainWindowController`側)がここから「取得すべきフォルダ」を決める。
    func effectivelyCheckedLeaves() -> [OneDriveFolderNode] {
        guard let root = rootNode else { return [] }
        return root.allLeaves().filter { isEffectivelyChecked($0) }
    }

    /// チェックされているのに、まだフェーズ2の取得が済んでいない葉フォルダ。
    /// チェックボックスをトグルして新しくチェックが入った(=これまで読み込んでいなかった)
    /// フォルダを検出し、その場で追加取得するために使う。
    func uncachedCheckedLeaves() -> [OneDriveFolderNode] {
        effectivelyCheckedLeaves().filter { !$0.itemsLoaded }
    }

    /// フェーズ2で1つの葉フォルダぶんの取得が完了するたびに呼ぶ。件数を反映して
    /// 祖先ノードの合計も更新し、ツリーの表示(`(件数)`)を再描画する。
    func recordLoadedItems(count: Int, at pathComponents: [String]) {
        guard let node = nodesByPath[pathComponents], node.isLeaf else { return }
        let delta = count - node.totalCount
        node.itemsLoaded = true
        node.totalCount = count
        var p = node.parent
        while let cur = p {
            cur.totalCount += delta
            p = cur.parent
        }
        outline.reloadData()
    }

    private func persistCheckedPaths() {
        var all = GallerySettings.folderTreeSelections
        all[link.id] = Self.encode(checkedPaths)
        GallerySettings.folderTreeSelections = all
    }

    /// パスコンポーネント配列は`Set`のCodable保存に向かないので`/`区切り文字列にする
    /// (ルート自身の`[]`は空文字列として扱う)。
    private static func encode(_ paths: Set<[String]>) -> Set<String> {
        Set(paths.map { $0.joined(separator: "/") })
    }
    private static func decode(_ paths: Set<String>) -> Set<[String]> {
        Set(paths.map { $0.isEmpty ? [] : $0.components(separatedBy: "/") })
    }

    private func allPaths(in node: OneDriveFolderNode) -> Set<[String]> {
        var s: Set<[String]> = [node.pathComponents]
        for c in node.children { s.formUnion(allPaths(in: c)) }
        return s
    }

    private func isEffectivelyChecked(_ node: OneDriveFolderNode) -> Bool {
        var n: OneDriveFolderNode? = node
        while let cur = n {
            if checkedPaths.contains(cur.pathComponents) { return true }
            n = cur.parent
        }
        return false
    }

    private func checkedCount(in node: OneDriveFolderNode) -> Int {
        if isEffectivelyChecked(node) { return node.totalCount }
        return node.children.reduce(0) { $0 + checkedCount(in: $1) }
    }

    /// チェック中でまだフェーズ2の取得が済んでいない葉フォルダは件数の代わりに
    /// 「…」を出す(0件と誤解されないように)。
    private func countLabel(for node: OneDriveFolderNode) -> String {
        if node.isLeaf, isEffectivelyChecked(node), !node.itemsLoaded { return "…" }
        return "\(checkedCount(in: node))"
    }

    /// `allItems`(読み込み済みの全件)のうち、現在のチェック状態で表示対象になるものだけを返す。
    /// ローカルの`PhotoStore.photos(checkedPaths:order:)`と同じ「チェック済みパスのいずれかが
    /// 祖先(または自分自身)なら含める」判定を、URLパスではなく`folderPath`の配列プレフィックス
    /// 一致で行う。
    func filteredItems(from allItems: [PhotoItem]) -> [PhotoItem] {
        guard !checkedPaths.isEmpty else { return [] }
        return allItems.filter { item in
            checkedPaths.contains { checked in
                item.folderPath.count >= checked.count && Array(item.folderPath.prefix(checked.count)) == checked
            }
        }
    }

    @objc private func checkboxToggled(_ sender: OneDriveTreeCheckbox) {
        guard let node = sender.node else { return }
        let affected = allPaths(in: node)
        if sender.state == .on {
            checkedPaths.formUnion(affected)
        } else {
            checkedPaths.subtract(affected)
        }
        outline.reloadData()
        persistCheckedPaths()
        onCheckedChanged?()
    }

    // MARK: data source

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNode == nil ? 0 : 1 }
        return (item as! OneDriveFolderNode).children.count
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNode! }
        return (item as! OneDriveFolderNode).children[index]
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !(item as! OneDriveFolderNode).children.isEmpty
    }

    // MARK: delegate

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! OneDriveFolderNode
        let cell = ov.makeView(withIdentifier: cellID, owner: nil) as? OneDriveFolderTreeCellView ?? makeCell()
        let isRoot = node === rootNode
        guard let checkbox = cell.checkbox as? OneDriveTreeCheckbox else { return cell }
        checkbox.node = node
        checkbox.state = checkedPaths.contains(node.pathComponents) ? .on : .off
        cell.textField?.stringValue = (isRoot ? "すべて" : node.name) + " (\(countLabel(for: node)))"
        cell.imageView?.image = NSImage(
            systemSymbolName: isRoot ? "photo.on.rectangle" : "folder",
            accessibilityDescription: nil)
        return cell
    }

    private func makeCell() -> OneDriveFolderTreeCellView {
        let cell = OneDriveFolderTreeCellView()
        cell.identifier = cellID
        let checkbox = OneDriveTreeCheckbox(checkboxWithTitle: "", target: self, action: #selector(checkboxToggled(_:)))
        let iv = NSImageView()
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let stack = NSStackView(views: [checkbox, iv, tf])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        cell.checkbox = checkbox
        cell.imageView = iv
        cell.textField = tf
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

private final class OneDriveTreeCheckbox: NSButton {
    weak var node: OneDriveFolderNode?
}

private final class OneDriveFolderTreeCellView: NSTableCellView {
    var checkbox: NSButton!
}

// MARK: - Local / 動画(OD) / 画像(OD) mode switch container

/// サイドバー上部の「ローカル」/「動画(OD)」/「画像(OD)」セグメントコントロールと、
/// 選択に応じて中身を差し替えるコンテナ。既存の`SidebarViewController`(ローカル
/// フォルダツリー)は変更せずそのまま使う。
enum SidebarMode {
    case local, video, photo
}

final class SidebarModeContainerViewController: NSViewController {
    let localVC: SidebarViewController
    let videoVC = OneDriveFolderTreeViewController(link: OneDriveLinks.video)
    let photoVC = OneDriveFolderTreeViewController(link: OneDriveLinks.photo)
    private let segmented = NSSegmentedControl(labels: ["ローカル", "ビデオ", "写真"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private var contentContainer = NSView()
    private var currentChild: NSViewController?

    /// モードが切り替わるたびに呼ばれる(`MainWindowController`がグリッドの読み込みを行う)。
    var onModeChanged: ((SidebarMode) -> Void)?

    /// 現在表示中のモード。`MainWindowController.refresh(_:)`が「今どちらのOneDriveタブを
    /// 見ているか(ビデオ/写真)」を判定して再読み込み対象の`videoVC`/`photoVC`を選ぶために
    /// 参照する(2026-09-07追加)。
    private(set) var currentMode: SidebarMode = .local

    init(localVC: SidebarViewController) {
        self.localVC = localVC
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 0, right: 8)
        container.frame = NSRect(x: 0, y: 0, width: 220, height: 600)

        segmented.target = self
        segmented.action = #selector(modeChanged)
        segmented.selectedSegment = 0
        segmented.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(segmented)
        container.addArrangedSubview(contentContainer)
        contentContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        // `OneDriveFolderTreeViewController`の同じ箇所のコメント参照 ― 垂直`NSStackView`の
        // デフォルト`alignment`は幅を埋めてくれない。ここは3タブすべての中身が乗る
        // 一番外側のコンテナなので、ここで幅を明示しないと配下すべて(局所的な
        // `viewDidLayout`での列幅同期を含め)が実際のサイドバー幅より狭いまま堂々巡りになる。
        contentContainer.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        view = container
        showChild(localVC)
    }

    private func showChild(_ vc: NSViewController) {
        if let current = currentChild {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentChild = vc
    }

    @objc private func modeChanged() {
        let mode: SidebarMode
        switch segmented.selectedSegment {
        case 1: mode = .video
        case 2: mode = .photo
        default: mode = .local
        }
        currentMode = mode
        showChild(child(for: mode))
        onModeChanged?(mode)
    }

    private func child(for mode: SidebarMode) -> NSViewController {
        switch mode {
        case .local: return localVC
        case .video: return videoVC
        case .photo: return photoVC
        }
    }

    /// ⌘Oでのローカルフォルダオープン等、OneDriveタブ表示中でもローカル専用の操作が
    /// 呼ばれたときに強制的にローカルモードへ戻す(呼び出し元の`MainWindowController`が
    /// `setRoot(_:)`の冒頭で呼ぶ)。既にローカルモードなら何もしない。
    func switchToLocal() {
        guard segmented.selectedSegment != 0 else { return }
        segmented.selectedSegment = 0
        modeChanged()
    }
}
