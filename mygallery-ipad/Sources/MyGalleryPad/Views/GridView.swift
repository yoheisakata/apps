import SwiftUI

/// サムネイルグリッド画面。**mygallery(Mac版)のグリッド+ビューアという体験を
/// SwiftUIで新規に書き起こしたもの**(myslideshow-ipad/mytube-ipadのどちらにも
/// 対応物が無い、MyGallery Padで初めて必要になった画面)。ホーム画面
/// (`Views/HomeView.swift`)で選んだ年/月フォルダの写真・動画を`LazyVGrid`で
/// 一覧表示し、タップすると`Views/ViewerView.swift`(全画面の1件ビューア)を開く。
/// ツールバーの再生ボタンから、今表示中のアイテム全体を対象にスライドショー
/// (`Views/SlideshowView.swift`、myslideshow-ipadからほぼそのまま移植)を開始できる。
struct GridView: View {
    let items: [MediaItem]
    let onBack: () -> Void
    let onReload: () -> Void
    let shuffleEnabled: Bool

    @State private var selectedIndex: Int?
    @State private var isShowingSlideshow = false

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    Text("写真・動画がありません")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ThumbnailCell(item: item)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .onTapGesture { selectedIndex = index }
                        }
                    }
                    .padding(4)
                }
            }
            .navigationTitle("MyGallery Pad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("戻る", systemImage: "chevron.left") { onBack() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("再読み込み", systemImage: "arrow.clockwise") { onReload() }
                    Button("スライドショー", systemImage: "play.rectangle") { isShowingSlideshow = true }
                        .disabled(items.isEmpty)
                }
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

    @State private var slideshowStartIndex = 0
}

/// グリッド1マスぶんのサムネイル。表示のたびに`ImageLoader.thumbnail(for:)`を
/// 非同期で読み込む(`AsyncImage`ではなくこの方式にしたのは、`downloadURL`
/// フォールバック込みのキャッシュロジックを`ImageLoader`側に一元化しているため)。
private struct ThumbnailCell: View {
    let item: MediaItem
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
        }
        .task(id: item.id) {
            image = await ImageLoader.shared.thumbnail(for: item)
        }
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
