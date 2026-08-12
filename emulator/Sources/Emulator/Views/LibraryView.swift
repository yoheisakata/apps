import SwiftUI

enum LibraryPage: String, CaseIterable, Identifiable {
    case nes = "NES"
    case snes = "SNES"
    case favorites = "favorites"
    case frequent = "frequent"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nes: return GameSystem.nes.displayName
        case .snes: return GameSystem.snes.displayName
        case .favorites: return "お気に入り"
        case .frequent: return "よく起動"
        }
    }

    var system: GameSystem? {
        switch self {
        case .nes: return .nes
        case .snes: return .snes
        default: return nil
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var emulator: EmulatorViewModel
    @ObservedObject var scanner: ROMScanner
    @ObservedObject var thumbnails = ThumbnailLoader.shared
    @ObservedObject var store = LibraryStore.shared
    @State private var searchText = ""
    @AppStorage("librarySystemFilter") private var selectedPageRaw = LibraryPage.nes.rawValue
    @State private var scanTriggered = false

    private var page: LibraryPage {
        LibraryPage(rawValue: selectedPageRaw) ?? .nes
    }

    /// よく起動したタイトルの表示上限
    private let frequentLimit = 20
    @State private var selection = Set<String>()
    @State private var pendingDelete: [ScannedROM] = []
    @State private var showDeleteConfirm = false
    @State private var selectedCategory: String?

    private var availableCategories: [String] {
        Set(scanner.roms.map(\.category)).sorted()
    }

    private var filteredROMs: [ScannedROM] {
        var results: [ScannedROM]
        switch page {
        case .nes, .snes:
            results = scanner.roms.filter { $0.system == page.system }
        case .favorites:
            results = scanner.roms.filter { store.favorites.contains($0.id) }
        case .frequent:
            results = scanner.roms
                .filter { (store.launchCounts[$0.id] ?? 0) > 0 }
                .sorted {
                    let a = store.launchCounts[$0.id] ?? 0
                    let b = store.launchCounts[$1.id] ?? 0
                    if a != b { return a > b }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            results = Array(results.prefix(frequentLimit))
        }
        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            results = results.filter { $0.displayName.lowercased().contains(q) }
        }
        return results
    }

    private var pendingCount: Int {
        scanner.roms.filter { !thumbnails.isMatched($0.id) && !thumbnails.isFailed($0.id) }.count
    }

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if scanner.romDirectory == nil {
                noFolderState
            } else if scanner.isScanning {
                scanningState
            } else if scanner.roms.isEmpty {
                emptyROMState
            } else {
                ScrollView {
                    if pendingCount > 0 {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("サムネイル取得中… (\(pendingCount) 残り)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }

                    if filteredROMs.isEmpty {
                        noMatchState
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredROMs) { rom in
                                ROMCard(rom: rom,
                                        thumbnail: thumbnails.images[rom.id],
                                        isSelected: selection.contains(rom.id),
                                        isFavorite: store.isFavorite(rom.id))
                                    .onTapGesture {
                                        if NSEvent.modifierFlags.contains(.command) {
                                            toggleSelection(rom)
                                        } else if selection.isEmpty {
                                            store.recordLaunch(rom.id)
                                            emulator.loadROM(url: rom.url)
                                        } else {
                                            toggleSelection(rom)
                                        }
                                    }
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.pointingHand.set()
                                        } else {
                                            NSCursor.arrow.set()
                                        }
                                    }
                                    .contextMenu {
                                        if selection.contains(rom.id) && selection.count > 1 {
                                            let allFav = selectedROMs.allSatisfy { store.isFavorite($0.id) }
                                            Button {
                                                for r in selectedROMs {
                                                    if allFav {
                                                        store.removeFavorite(r.id)
                                                    } else {
                                                        store.addFavorite(r.id)
                                                    }
                                                }
                                            } label: {
                                                Label(allFav ? "選択した \(selection.count) 件をお気に入りから外す"
                                                             : "選択した \(selection.count) 件をお気に入りに追加",
                                                      systemImage: allFav ? "star.slash" : "star")
                                            }
                                            Button {
                                                rotateSelected()
                                            } label: {
                                                Label("選択した \(selection.count) 件のサムネイルを90°回転", systemImage: "rotate.right")
                                            }
                                            Divider()
                                            Button(role: .destructive) {
                                                requestDelete(selectedROMs)
                                            } label: {
                                                Label("選択した \(selection.count) 件をゴミ箱に入れる", systemImage: "trash")
                                            }
                                        } else {
                                            Button {
                                                store.toggleFavorite(rom.id)
                                            } label: {
                                                Label(store.isFavorite(rom.id) ? "お気に入りから外す" : "お気に入りに追加",
                                                      systemImage: store.isFavorite(rom.id) ? "star.slash" : "star")
                                            }
                                            if thumbnails.images[rom.id] != nil {
                                                Button {
                                                    thumbnails.rotate(id: rom.id)
                                                } label: {
                                                    Label("サムネイルを90°回転", systemImage: "rotate.right")
                                                }
                                            }
                                            Divider()
                                            Button(role: .destructive) {
                                                requestDelete([rom])
                                            } label: {
                                                Label("「\(rom.displayName)」をゴミ箱に入れる", systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(20)
                    }
                }
            }

            Divider()
            statusBar
        }
        .onAppear {
            if !scanTriggered && !scanner.roms.isEmpty {
                thumbnails.loadAll(roms: scanner.roms)
                scanTriggered = true
            }
        }
        .onChange(of: scanner.roms) { _, roms in
            thumbnails.loadAll(roms: roms)
            selection = selection.filter { id in roms.contains { $0.id == id } }
        }
        .alert("ゴミ箱に入れますか?", isPresented: $showDeleteConfirm) {
            Button("ゴミ箱に入れる", role: .destructive) {
                scanner.moveToTrash(pendingDelete)
                selection.removeAll()
                pendingDelete = []
            }
            Button("キャンセル", role: .cancel) {
                pendingDelete = []
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private func chipLabel(for p: LibraryPage) -> String {
        switch p {
        case .nes, .snes:
            let count = scanner.roms.filter { $0.system == p.system }.count
            return "\(p.displayName) (\(count))"
        case .favorites:
            let count = scanner.roms.filter { store.favorites.contains($0.id) }.count
            return "\(p.displayName) (\(count))"
        case .frequent:
            return p.displayName
        }
    }

    // MARK: - Selection / Delete

    private var selectedROMs: [ScannedROM] {
        scanner.roms.filter { selection.contains($0.id) }
    }

    private func toggleSelection(_ rom: ScannedROM) {
        if selection.contains(rom.id) {
            selection.remove(rom.id)
        } else {
            selection.insert(rom.id)
        }
    }

    private func rotateSelected() {
        for rom in selectedROMs {
            thumbnails.rotate(id: rom.id)
        }
    }

    private func requestDelete(_ roms: [ScannedROM]) {
        guard !roms.isEmpty else { return }
        pendingDelete = roms
        showDeleteConfirm = true
    }

    private var deleteMessage: String {
        let names = pendingDelete.prefix(3).map { "「\($0.displayName)」" }.joined(separator: "、")
        let more = pendingDelete.count > 3 ? " ほか \(pendingDelete.count - 3) 件" : ""
        return "\(names)\(more) の ROM ファイルをゴミ箱に入れます。"
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.secondary)
                Text("ゲームライブラリ")
                    .font(.title2.bold())
                Spacer()

                if !scanner.roms.isEmpty {
                    TextField("検索…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                Button(action: { scanner.chooseDirectory() }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("ROMフォルダを選択")

                if scanner.romDirectory != nil {
                    Button(action: { scanner.rescan() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("再スキャン")
                }
            }

            if !scanner.roms.isEmpty {
                HStack(spacing: 4) {
                    ForEach(LibraryPage.allCases) { p in
                        FilterChip(label: chipLabel(for: p), isSelected: page == p) {
                            selectedPageRaw = p.rawValue
                        }
                    }
                    Spacer()
                }
            }

            if availableCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        FilterChip(label: "すべて", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(availableCategories, id: \.self) { category in
                            FilterChip(label: category, isSelected: selectedCategory == category) {
                                selectedCategory = selectedCategory == category ? nil : category
                            }
                        }
                    }
                }
            }

            if !selection.isEmpty {
                HStack(spacing: 8) {
                    Text("\(selection.count) 件選択中")
                        .font(.caption.bold())
                    Button {
                        rotateSelected()
                    } label: {
                        Label("90°回転", systemImage: "rotate.right")
                            .font(.caption)
                    }
                    Button(role: .destructive) {
                        requestDelete(selectedROMs)
                    } label: {
                        Label("ゴミ箱に入れる", systemImage: "trash")
                            .font(.caption)
                    }
                    Button("選択解除") {
                        selection.removeAll()
                    }
                    .font(.caption)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - States

    private var noFolderState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("ROMフォルダが設定されていません")
                .font(.headline)
            Text("ROM ファイル (.nes, .sfc, .smc) を含むフォルダを選択してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("フォルダを選択…") {
                scanner.chooseDirectory()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("ROMをスキャン中…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyROMState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("ROM ファイルが見つかりません")
                .font(.headline)
            if let error = scanner.scanError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if let dir = scanner.romDirectory {
                Text(dir.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("別のフォルダを選択…") {
                scanner.chooseDirectory()
            }
            Spacer()
        }
        .padding()
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: page == .favorites ? "star" : page == .frequent ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(noMatchMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private var noMatchMessage: String {
        if !searchText.isEmpty { return "該当するタイトルがありません" }
        switch page {
        case .favorites:
            return "お気に入りはまだありません。\nタイトルを右クリック →「お気に入りに追加」で登録できます"
        case .frequent:
            return "起動履歴はまだありません。\nゲームを起動すると回数の多い順に最大\(frequentLimit)件表示されます"
        default:
            return "該当するタイトルがありません"
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if let status = scanner.scanStatus {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let dir = scanner.romDirectory {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(dir.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let error = scanner.scanError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Text("⌘クリックで複数選択")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("\(filteredROMs.count) / \(scanner.roms.count) タイトル(カバーアート \(scanner.roms.filter { thumbnails.isMatched($0.id) }.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - ROM Card

struct ROMCard: View {
    let rom: ScannedROM
    let thumbnail: NSImage?
    var isSelected: Bool = false
    var isFavorite: Bool = false

    // 枠を画像自身の縦横比に合わせる(ファミコンの横長パッケージが
    // 縦長枠の余白に埋もれて小さく表示されるのを防ぐ)
    private var imageAspect: CGFloat {
        if let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 {
            return thumbnail.size.width / thumbnail.size.height
        }
        return 3.0 / 4.0
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if let image = thumbnail {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: rom.system == .nes
                                ? [Color(red: 0.55, green: 0.15, blue: 0.15), Color(red: 0.3, green: 0.08, blue: 0.08)]
                                : [Color(red: 0.2, green: 0.25, blue: 0.55), Color(red: 0.1, green: 0.12, blue: 0.3)],
                            startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(rom.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
            .aspectRatio(imageAspect, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 2) {
                Text(rom.displayName)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(rom.system.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(rom.system == .nes ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                    .foregroundStyle(rom.system == .nes ? .red : .blue)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
    }
}
