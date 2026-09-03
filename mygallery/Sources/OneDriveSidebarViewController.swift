import AppKit

// OneDrive 共有リンクのブラウズ UI(MySlideshow にはない、MyGallery だけの新機能 —
// MySlideshow はリンクが2つの決め打ち配列で追加・削除UIを持たなかったが、MyGallery は
// 汎用ギャラリーアプリなので追加・削除できる方が自然、という判断でこの UI を新設した)。

// MARK: - Settings (UserDefaults)

/// OneDrive関連の設定の一元管理(myslideshowの`Core/Settings.swift`と同じ方針)。
enum GallerySettings {
    private static let oneDriveLinksKey = "mygallery.oneDriveLinks"
    private static let folderSelectionsKey = "mygallery.folderSelections"
    private static let slideshowPhotoDurationKey = "mygallery.slideshowPhotoDurationSeconds"
    private static let slideshowShuffleKey = "mygallery.slideshowShuffleEnabled"
    private static let slideshowTimeLimitKey = "mygallery.slideshowTimeLimitMinutes"
    private static let slideshowAutoFullscreenKey = "mygallery.slideshowAutoFullscreen"

    /// MySlideshow(廃止済み)が使っていた2リンク(動画専用「動画」・写真専用「写真」、
    /// ともに2020〜2026年フォルダ)を初回起動時のデフォルトとして引き継ぐ。
    private static let defaultLinks: [OneDriveLink] = [
        OneDriveLink(
            name: "動画",
            url: "https://1drv.ms/f/c/6b83b2b7da86a08f/IgCnAW6bjrzaQ5MFMH8h-w3oAbOsSLkLLLzMzHoMxn_CWzo?e=YS9SKE",
            kindFilter: .video,
            availableFolders: ["2020", "2021", "2022", "2023", "2024", "2025", "2026"]
        ),
        OneDriveLink(
            name: "写真",
            url: "https://1drv.ms/f/c/22558ab42b6166a7/IgCnZmErtIpVIIAi9kQGAAAAATumoVsXYR__s2VdsQrfg00?e=VCUJRX",
            kindFilter: .photo,
            availableFolders: ["2020", "2021", "2022", "2023", "2024", "2025", "2026"]
        ),
    ]

    static var oneDriveLinks: [OneDriveLink] {
        get {
            guard let data = UserDefaults.standard.data(forKey: oneDriveLinksKey) else {
                return defaultLinks
            }
            return (try? JSONDecoder().decode([OneDriveLink].self, from: data)) ?? defaultLinks
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: oneDriveLinksKey)
        }
    }

    /// リンクごとに選んだフォルダ名の集合。キーは`OneDriveLink.id`(URL文字列)。
    /// 未保存(キー無し)は「全フォルダ対象」を意味する。
    static var folderSelections: [String: Set<String>] {
        get {
            guard let data = UserDefaults.standard.data(forKey: folderSelectionsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Set<String>].self, from: data)) ?? [:]
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: folderSelectionsKey)
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

/// MyGalleryで追加・削除できるOneDrive共有リンク(MySlideshowの`HardcodedLink`と違い
/// `Codable`にしてUserDefaultsへ永続化する)。
struct OneDriveLink: Codable, Identifiable, Equatable {
    var id: String { url }
    var name: String
    var url: String
    /// 対象を絞る場合のメディア種別(nilなら写真・動画どちらも対象)。
    var kindFilter: MediaKind?
    /// 選べるフォルダ名の一覧。リンク追加時に`OneDriveMediaClient.listTopLevelFolders`で
    /// 自動取得する(MySlideshowは決め打ち配列だったが、任意のリンクを扱うMyGalleryでは
    /// 自動取得が必須)。
    var availableFolders: [String]
}

/// OneDriveのフォルダ木構造の1ノード(サイドバーの`NSOutlineView`の item として使う)。
private final class OneDriveOutlineLinkNode: NSObject {
    let link: OneDriveLink
    init(link: OneDriveLink) { self.link = link }
}
private final class OneDriveOutlineFolderNode: NSObject {
    let linkID: String
    let folderName: String
    init(linkID: String, folderName: String) {
        self.linkID = linkID
        self.folderName = folderName
    }
}

// MARK: - Sidebar view controller

final class OneDriveSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outline = NSOutlineView()
    private let cellID = NSUserInterfaceItemIdentifier("OneDriveSidebarCell")
    private let loadButton = NSButton(title: "読み込み", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private(set) var links: [OneDriveLink] = []
    private var folderSelections: [String: Set<String>] = [:]

    /// 選んだリンク+フォルダの読み込みを要求されたときに呼ばれる
    /// (`MainWindowController`が実際のスキャン・グリッドへの反映を行う)。
    var onLoadRequested: ((OneDriveLink, Set<String>) -> Void)?
    /// リンク一覧が変わった(追加・削除)ときに呼ばれる。
    var onLinksChanged: (() -> Void)?

    override func loadView() {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 8, right: 8)
        container.frame = NSRect(x: 0, y: 0, width: 220, height: 600)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("onedrive"))
        col.isEditable = false
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.allowsEmptySelection = true
        outline.selectionHighlightStyle = .regular
        outline.dataSource = self
        outline.delegate = self
        outline.autoresizesOutlineColumn = true
        outline.target = self
        outline.action = #selector(outlineClicked)
        scroll.documentView = outline
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "リンクを追加")!,
                                  target: self, action: #selector(addLink))
        addButton.bezelStyle = .smallSquare
        addButton.isBordered = false
        let removeButton = NSButton(image: NSImage(systemSymbolName: "minus", accessibilityDescription: "リンクを削除")!,
                                     target: self, action: #selector(removeSelectedLink))
        removeButton.bezelStyle = .smallSquare
        removeButton.isBordered = false
        let buttonsRow = NSStackView(views: [addButton, removeButton, NSView()])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 2

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        loadButton.target = self
        loadButton.action = #selector(loadTapped)
        loadButton.bezelStyle = .rounded

        container.addArrangedSubview(scroll)
        container.addArrangedSubview(buttonsRow)
        container.addArrangedSubview(statusLabel)
        container.addArrangedSubview(loadButton)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        loadButton.translatesAutoresizingMaskIntoConstraints = false

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        links = GallerySettings.oneDriveLinks
        folderSelections = GallerySettings.folderSelections
        outline.reloadData()
        for link in links { outline.expandItem(OneDriveOutlineLinkNode(link: link)) }
    }

    func setStatus(_ text: String) { statusLabel.stringValue = text }

    // MARK: add / remove link

    @objc private func addLink() {
        let alert = NSAlert()
        alert.messageText = "OneDriveリンクを追加"
        alert.informativeText = "共有リンクの名前とURLを入力してください。"
        alert.addButton(withTitle: "追加")
        alert.addButton(withTitle: "キャンセル")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 90)

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "名前(例: 家族の写真)"
        let urlField = NSTextField(string: "")
        urlField.placeholderString = "OneDrive共有URL(https://1drv.ms/...)"
        let kindPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        kindPopup.addItems(withTitles: ["写真・動画どちらも", "写真のみ", "動画のみ"])

        for f in [nameField, urlField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(urlField)
        stack.addArrangedSubview(kindPopup)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !urlString.isEmpty else { return }
        let kindFilter: MediaKind? = kindPopup.indexOfSelectedItem == 1 ? .photo
            : (kindPopup.indexOfSelectedItem == 2 ? .video : nil)

        setStatus("フォルダ一覧を取得中…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let folders = try await OneDriveMediaClient.listTopLevelFolders(shareURL: urlString)
                await MainActor.run {
                    let link = OneDriveLink(name: name, url: urlString, kindFilter: kindFilter,
                                             availableFolders: folders)
                    self.links.append(link)
                    GallerySettings.oneDriveLinks = self.links
                    self.setStatus("")
                    self.outline.reloadData()
                    self.outline.expandItem(OneDriveOutlineLinkNode(link: link))
                    self.onLinksChanged?()
                }
            } catch {
                await MainActor.run {
                    self.setStatus("")
                    let a = NSAlert()
                    a.messageText = "リンクを追加できませんでした"
                    a.informativeText = error.localizedDescription
                    a.runModal()
                }
            }
        }
    }

    @objc private func removeSelectedLink() {
        let item = outline.item(atRow: outline.selectedRow)
        guard let linkNode = item as? OneDriveOutlineLinkNode else { return }
        links.removeAll { $0.id == linkNode.link.id }
        folderSelections.removeValue(forKey: linkNode.link.id)
        GallerySettings.oneDriveLinks = links
        GallerySettings.folderSelections = folderSelections
        outline.reloadData()
        onLinksChanged?()
    }

    @objc private func outlineClicked() {
        let item = outline.item(atRow: outline.clickedRow)
        guard let folderNode = item as? OneDriveOutlineFolderNode,
              let cell = outline.view(atColumn: 0, row: outline.clickedRow, makeIfNecessary: false) as? OneDriveSidebarCellView,
              let checkbox = cell.checkbox as? OneDriveFolderCheckbox
        else { return }
        checkbox.state = (checkbox.state == .on) ? .off : .on
        toggleFolder(checkbox)
        _ = folderNode
    }

    @objc private func toggleFolder(_ sender: OneDriveFolderCheckbox) {
        var selected = folderSelections[sender.linkID] ?? Set(links.first { $0.id == sender.linkID }?.availableFolders ?? [])
        if sender.state == .on {
            selected.insert(sender.folderName)
        } else {
            selected.remove(sender.folderName)
        }
        folderSelections[sender.linkID] = selected
        GallerySettings.folderSelections = folderSelections
    }

    @objc private func loadTapped() {
        let item = outline.item(atRow: outline.selectedRow)
        let linkNode: OneDriveOutlineLinkNode?
        switch item {
        case let n as OneDriveOutlineLinkNode: linkNode = n
        case let f as OneDriveOutlineFolderNode: linkNode = links.first { $0.id == f.linkID }.map(OneDriveOutlineLinkNode.init)
        default: linkNode = nil
        }
        guard let node = linkNode else {
            setStatus("リンクを選択してください")
            return
        }
        let selected = folderSelections[node.link.id] ?? Set(node.link.availableFolders)
        onLoadRequested?(node.link, selected)
    }

    // MARK: data source

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return links.count }
        if let link = (item as? OneDriveOutlineLinkNode)?.link { return link.availableFolders.count }
        return 0
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return OneDriveOutlineLinkNode(link: links[index]) }
        let link = (item as! OneDriveOutlineLinkNode).link
        return OneDriveOutlineFolderNode(linkID: link.id, folderName: link.availableFolders[index])
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let link = (item as? OneDriveOutlineLinkNode)?.link { return !link.availableFolders.isEmpty }
        return false
    }

    // MARK: delegate

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let linkNode = item as? OneDriveOutlineLinkNode {
            let cell = ov.makeView(withIdentifier: cellID, owner: nil) as? OneDriveSidebarCellView ?? makeCell(checkbox: false)
            cell.checkbox?.isHidden = true
            cell.textField?.stringValue = linkNode.link.name
            cell.imageView?.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: nil)
            return cell
        }
        let folderNode = item as! OneDriveOutlineFolderNode
        let cell = ov.makeView(withIdentifier: cellID, owner: nil) as? OneDriveSidebarCellView ?? makeCell(checkbox: true)
        guard let checkbox = cell.checkbox as? OneDriveFolderCheckbox else { return cell }
        checkbox.isHidden = false
        checkbox.linkID = folderNode.linkID
        checkbox.folderName = folderNode.folderName
        let selected = folderSelections[folderNode.linkID]
            ?? Set(links.first { $0.id == folderNode.linkID }?.availableFolders ?? [])
        checkbox.state = selected.contains(folderNode.folderName) ? .on : .off
        cell.textField?.stringValue = folderNode.folderName
        cell.imageView?.image = nil
        return cell
    }

    private func makeCell(checkbox hasCheckbox: Bool) -> OneDriveSidebarCellView {
        let cell = OneDriveSidebarCellView()
        cell.identifier = cellID
        let checkbox = OneDriveFolderCheckbox(checkboxWithTitle: "", target: self, action: #selector(toggleFolder(_:)))
        let iv = NSImageView()
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(checkbox)
        cell.addSubview(iv)
        cell.addSubview(tf)
        cell.checkbox = checkbox
        cell.imageView = iv
        cell.textField = tf
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// フォルダ行のチェックボックス。再利用されるセルからどのリンク・フォルダ名に対応するか
/// 引けるよう、識別子を直接持たせる(main.swiftの`SidebarCheckbox`と同じ発想 ―
/// あちらは`private`でこのファイルから参照できないため、同じ形を独自に定義する)。
private final class OneDriveFolderCheckbox: NSButton {
    var linkID: String = ""
    var folderName: String = ""
}

/// main.swiftの`SidebarCellView`と同じ形だが`private`で参照できないため独自に定義する。
private final class OneDriveSidebarCellView: NSTableCellView {
    var checkbox: NSButton!
}

// MARK: - Local / OneDrive mode switch container

/// サイドバー上部の「ローカル」/「OneDrive」セグメントコントロールと、選択に応じて
/// 中身を差し替えるコンテナ。既存の`SidebarViewController`(ローカルフォルダツリー)は
/// 変更せずそのまま使う。
final class SidebarModeContainerViewController: NSViewController {
    let localVC: SidebarViewController
    let oneDriveVC = OneDriveSidebarViewController()
    private let segmented = NSSegmentedControl(labels: ["ローカル", "OneDrive"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private var contentContainer = NSView()
    private var currentChild: NSViewController?

    /// モードが切り替わるたびに呼ばれる(`MainWindowController`が`isOneDriveMode`を同期する)。
    var onModeChanged: ((Bool) -> Void)?

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
        let isOneDrive = segmented.selectedSegment == 1
        showChild(isOneDrive ? oneDriveVC : localVC)
        onModeChanged?(isOneDrive)
    }

    /// ⌘Oでのローカルフォルダオープン等、OneDriveモード中でもローカル専用の操作が
    /// 呼ばれたときに強制的にローカルモードへ戻す(呼び出し元の`MainWindowController`が
    /// `setRoot(_:)`の冒頭で呼ぶ)。既にローカルモードなら何もしない。
    func switchToLocal() {
        guard segmented.selectedSegment != 0 else { return }
        segmented.selectedSegment = 0
        modeChanged()
    }
}
