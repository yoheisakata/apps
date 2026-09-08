import SwiftUI

/// サムネイルグリッド画面。**mygallery(Mac版)のグリッド+ビューアという体験を
/// SwiftUIで新規に書き起こしたもの**(myslideshow-ipad/mytube-ipadのどちらにも
/// 対応物が無い、MyGallery Padで初めて必要になった画面)。選択中のOneDriveリンクの
/// 写真・動画(`Views/LinkDetailView.swift`が渡す)を`LazyVGrid`で一覧表示し、
/// タップすると`Views/ViewerView.swift`(全画面の1件ビューア)を開く。ツールバーの
/// 再生ボタンから、今表示中のアイテム全体を対象にスライドショー
/// (`Views/SlideshowView.swift`、myslideshow-ipadからほぼそのまま移植)を開始できる。
///
/// mytube-ipadの`VideoLibraryView`と同じく、**このビュー自体は`NavigationStack`を
/// 持たない**(`ContentView`の`NavigationSplitView`のdetailに直接収まる前提。
/// `.navigationTitle`/フォルダ選択の`.toolbar`は呼び出し元の`LinkDetailView`が付ける ―
/// SwiftUIは同一ビュー系列上の複数の`.toolbar`修飾子を1つのナビゲーションバーへ
/// マージするため、ここで宣言する「スライドショー」ボタンと`LinkDetailView`側の
/// 「年/月を選ぶ」ボタンは同じツールバーに並ぶ)。以前の版にあった「戻る」
/// (ホーム画面へのブロッキング遷移)・「再読み込み」ボタンは、`NavigationSplitView`
/// 化でサイドバー選択がそのままナビゲーションになったため撤去した(再読み込みは
/// `LinkDetailView`の`.refreshable`のプルダウンに統合)。
struct GridView: View {
    let items: [MediaItem]
    /// フェーズ2スキャン中かどうか(`LinkDetailView`が渡す)。一覧が空のときだけ
    /// 全画面のローディング表示を出す(一覧が既にある状態でのバックグラウンド更新中は
    /// `LinkDetailView`側のツールバーの控えめな`ProgressView`に任せる ―
    /// mytube-ipadの`SourceGridView`/`RemoteListCache`と同じ考え方)。
    let isLoading: Bool
    let errorMessage: String?
    let shuffleEnabled: Bool
    /// 現在の並び替え順(2026-09-07追加)。日付順のときだけ、下記の年月区切り線を出す
    /// (mygallery Mac版の`sortOrder.isDateOrder`ゲートと同じ、`Core/SortOrder.swift`参照)。
    let sortOrder: SortOrder
    let showSizeBadge: Bool
    let showDateBadge: Bool

    @State private var selectedIndex: Int?
    @State private var isShowingSlideshow = false
    @State private var slideshowStartIndex = 0

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 4)]

    /// `items`(呼び出し元で既に`sortOrder`通りに並べ替え済み)を、フォルダパス
    /// (年/月)が変わるたびに新しい区切りにする「連続run」へ分割したもの。
    /// mygallery(Mac版)の`recomputeGroups()`と同じ考え方 ― 表示順そのものを
    /// 変えず、あくまで見出し表示用の派生データ。`items`のフラットな絶対インデックス
    /// (ビューア/スライドショーの開始位置に必要)を保つため、各グループに
    /// `startIndex`を持たせてある。
    private var groups: [ItemGroup] {
        guard sortOrder.isDateOrder, !items.isEmpty else {
            return [ItemGroup(key: "", items: Array(items.enumerated()))]
        }
        var result: [ItemGroup] = []
        var currentKey: String?
        var currentItems: [(offset: Int, element: MediaItem)] = []
        for (index, item) in items.enumerated() {
            let key = item.folderPath.joined(separator: "/")
            if key != currentKey {
                if let currentKey {
                    result.append(ItemGroup(key: currentKey, items: currentItems))
                }
                currentKey = key
                currentItems = []
            }
            currentItems.append((index, item))
        }
        if let currentKey {
            result.append(ItemGroup(key: currentKey, items: currentItems))
        }
        return result
    }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                if isLoading {
                    ProgressView("読み込み中…")
                        .padding(.top, 60)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 60)
                        .padding(.horizontal, 24)
                } else {
                    Text("写真・動画がありません")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(groups) { group in
                        // `Section`はLazyVGrid内でも使え、ヘッダーはグリッドの列割り
                        // (`columns`)には従わず1行まるごとを占める ― mygallery(Mac版)の
                        // `NSCollectionViewFlowLayout`セクションヘッダーと同じ見た目になる。
                        // グループが1つしかない(=区切る意味が無い、名前順/サイズ順や
                        // 単一フォルダのみの結果)ときは見出しを出さない ― Mac版が
                        // `groups.count > 1`のときだけヘッダーを出すのと同じ判断。
                        Section {
                            ForEach(group.items, id: \.element.id) { index, item in
                                ThumbnailCell(item: item, showSizeBadge: showSizeBadge || sortOrder.showsFileSize, showDateBadge: showDateBadge)
                                    .onTapGesture { selectedIndex = index }
                            }
                        } header: {
                            if sortOrder.isDateOrder, groups.count > 1 {
                                GroupHeader(title: group.key)
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("スライドショー", systemImage: "play.rectangle") { isShowingSlideshow = true }
                    .disabled(items.isEmpty)
            }
        }
        .fullScreenCover(item: $selectedIndex.toIdentifiableIndex()) { wrapped in
            ViewerView(
                items: items,
                startIndex: wrapped.index,
                onClose: { selectedIndex = nil },
                onStartSlideshow: { index in
                    selectedIndex = nil
                    // 選んだ位置から始められるよう、いったんビューアを閉じてから
                    // スライドショーへ移る(`slideshowStartIndex`経由)。
                    slideshowStartIndex = index
                    isShowingSlideshow = true
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingSlideshow) {
            SlideshowView(
                items: shuffleEnabled ? items.shuffled() : items,
                timeLimitMinutes: Settings.timeLimitMinutes,
                startIndex: shuffleEnabled ? 0 : slideshowStartIndex,
                onExit: { isShowingSlideshow = false; slideshowStartIndex = 0 }
            )
        }
    }
}

/// `GridView.groups`の1要素。フォルダパス(年/月)が同じ連続run。`items`は
/// `(offset: items配列でのフラットな絶対インデックス, element: MediaItem)`のペア ―
/// `ForEach`のタップハンドラがビューア起動時に元の`items`配列上の位置を渡せるようにする。
private struct ItemGroup: Identifiable {
    let key: String
    let items: [(offset: Int, element: MediaItem)]
    var id: String { key }
}

/// グリッドの年月区切り見出し。mygallery(Mac版)の`DateSectionHeaderView`
/// (タイトルラベル+水平線)と同じ見た目をSwiftUIで再現したもの。
private struct GroupHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .padding(.horizontal, 2)
    }
}

/// グリッド1マスぶんのサムネイル。表示のたびに`ImageLoader.thumbnail(for:)`を
/// 非同期で読み込む(`AsyncImage`ではなくこの方式にしたのは、`downloadURL`
/// フォールバック込みのキャッシュロジックを`ImageLoader`側に一元化しているため)。
///
/// **左上/右下バッジ(2026-09-07追加)**: mygallery(Mac版)の`PhotoCell`と同じ
/// 2スロット design ― 左上が月日バッジ(`showDateBadge`)、右下がファイルサイズ
/// バッジ(`showSizeBadge`、サイズ順ソート中は呼び出し元`GridView`が強制的に
/// `true`を渡す)。Mac版と違い画質バッジは無い(画質順ソート自体がこのアプリに
/// 無いため、右下スロットはサイズ専用でよい)。
private struct ThumbnailCell: View {
    let item: MediaItem
    let showSizeBadge: Bool
    let showDateBadge: Bool
    @State private var image: UIImage?

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        return formatter
    }()

    var body: some View {
        // `GeometryReader`で先に正方形の実サイズを確定させてから中身を敷き詰める。
        // 以前は外側に`.aspectRatio(1, contentMode: .fill)`を直接かけていたが、
        // `.fill`はセルの提案サイズより大きく育ってから`.clipped()`で描画だけを
        // 切り詰める挙動のため、`LazyVGrid`の行の高さ計算に実際より大きいサイズが
        // 伝わり、行同士が重なって見える不具合があった。ここでは正方形の枠自体は
        // `.fit`で確実に提案サイズ以下に収め、画像の中身だけ`.fill`+`.clipped()`で
        // 埋めるようにして重なりを解消した。
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                Rectangle().fill(Color.secondary.opacity(0.15))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipped()
                } else {
                    ProgressView()
                }
                if item.kind == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .padding(6)
                                .background(.black.opacity(0.5), in: Circle())
                                .foregroundStyle(.white)
                                .padding(4)
                            Spacer()
                        }
                    }
                }
                if showDateBadge, let text = dateBadgeText {
                    VStack {
                        HStack {
                            badgeLabel(text)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                if showSizeBadge {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            badgeLabel(Self.sizeFormatter.string(fromByteCount: item.size))
                        }
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: item.id) {
            image = await ImageLoader.shared.thumbnail(for: item)
        }
    }

    /// mygallery(Mac版)の月日バッジと同じ考え方: ファイル名から推測した撮影日
    /// (`MediaItem.capturedDate`)優先、無ければ`modifiedDate`(OneDriveの更新日時)へ
    /// フォールバックする。
    private var dateBadgeText: String? {
        guard let date = item.capturedDate ?? item.modifiedDate else { return nil }
        return Self.monthDayFormatter.string(from: date)
    }

    private func badgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .padding(4)
    }
}

/// `fullScreenCover(item:)`は`Identifiable`を要求するため、単純な`Int?`インデックスを
/// `Identifiable`にラップするための小さなヘルパー。
private struct IdentifiableIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

private extension Binding where Value == Int? {
    func toIdentifiableIndex() -> Binding<IdentifiableIndex?> {
        Binding<IdentifiableIndex?>(
            get: { self.wrappedValue.map(IdentifiableIndex.init) },
            set: { self.wrappedValue = $0?.index }
        )
    }
}
