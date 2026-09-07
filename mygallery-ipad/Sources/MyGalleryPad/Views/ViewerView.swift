import SwiftUI

/// グリッドでタップした位置から始まる、全画面の単体ビューア。**新規に書き起こした
/// 画面**(myslideshow-ipad/mytube-ipadのどちらにも対応物が無い) ― mygallery(Mac版)の
/// `ViewerOverlay`(ダブルクリックで開く、矢印キー/スワイプで前後移動、動画は
/// `AVPlayerView`で再生)に近い体験を、iPad向けに新規実装したもの。
///
/// **ページング方式は独自のスワイプ(`DragGesture`)+ボタン送り**にした(TabView(.page)
/// ではない) ― `Views/SlideshowView.swift`(myslideshow-ipadから移植)がすでに同じ
/// 「現在のインデックスを持ち、前後だけレンダリングする」設計を採用しており、
/// TabView(.page)は`AVPlayer`を持つページが隣接ページとして先読み保持される際に
/// 再生状態やメモリ管理が絡んで挙動が読みづらいため、実績のある自前のindex方式に
/// 揃えた。写真はタップでコントロール表示/非表示、動画は`AVPlayerViewController`の
/// 標準コントロール(`showsControls: true`)をそのまま使う ― スライドショーと違い
/// 手動視聴なのでシークバー等をユーザーが直接操作できた方が良いと判断した。
struct ViewerView: View {
    let items: [MediaItem]
    let startIndex: Int
    let onClose: () -> Void
    /// 現在の位置からスライドショーへ引き継ぐためのコールバック(押された時点の
    /// インデックスを渡す)。`Views/GridView.swift`が受け取ってスライドショーを開始する。
    let onStartSlideshow: (Int) -> Void

    @State private var currentIndex: Int
    @State private var currentImage: UIImage?
    @State private var loadToken = UUID()
    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var dragOffset: CGFloat = 0
    @StateObject private var engine = PlayerEngine()

    init(items: [MediaItem], startIndex: Int, onClose: @escaping () -> Void, onStartSlideshow: @escaping (Int) -> Void) {
        self.items = items
        self.startIndex = startIndex
        self.onClose = onClose
        self.onStartSlideshow = onStartSlideshow
        _currentIndex = State(initialValue: startIndex)
    }

    private var current: MediaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current {
                switch current.kind {
                case .photo:
                    if let currentImage {
                        Image(uiImage: currentImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .id(current.id)
                            .offset(x: dragOffset)
                    } else {
                        ProgressView().tint(.white).controlSize(.large)
                    }
                case .video:
                    NativeVideoPlayerView(player: engine.player, showsControls: true)
                        .id(current.id)
                        .ignoresSafeArea()
                }
            }

            if showsControls {
                topBar
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
        .contentShape(Rectangle())
        .onTapGesture { revealControls() }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard current?.kind == .photo else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    guard current?.kind == .photo else { return }
                    let threshold: CGFloat = 80
                    if value.translation.width < -threshold {
                        goNext()
                    } else if value.translation.width > threshold {
                        goPrevious()
                    }
                    dragOffset = 0
                }
        )
        .onKeyPress(.leftArrow) { goPrevious(); return .handled }
        .onKeyPress(.rightArrow) { goNext(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onAppear {
            revealControls()
            loadCurrent()
        }
        .onChange(of: currentIndex) { _, _ in loadCurrent() }
        .onDisappear { engine.stop() }
        .statusBarHidden()
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                }
                Spacer()
                if let current {
                    VStack(spacing: 2) {
                        Text(current.name)
                            .font(.caption)
                            .lineLimit(1)
                        if !items.isEmpty {
                            Text("\(currentIndex + 1) / \(items.count)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
                Button {
                    onStartSlideshow(currentIndex)
                } label: {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                }
            }
            .foregroundStyle(.white)
            .padding()
            .background(.black.opacity(0.55))

            Spacer()

            HStack(spacing: 40) {
                Button(action: goPrevious) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 40))
                }
                Button(action: goNext) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 40))
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.bottom, 40)
        }
    }

    private func loadCurrent() {
        engine.stop()
        currentImage = nil
        loadToken = UUID()
        guard let current else { return }
        switch current.kind {
        case .photo:
            let token = loadToken
            Task {
                let image = await ImageLoader.shared.image(for: current)
                guard token == loadToken else { return }
                currentImage = image
            }
            ImageLoader.shared.prefetch(upcoming())
        case .video:
            engine.load(url: current.downloadURL)
        }
    }

    private func upcoming(count: Int = 2) -> [MediaItem] {
        guard !items.isEmpty else { return [] }
        return (1...count).compactMap { offset in
            let idx = currentIndex + offset
            return items.indices.contains(idx) ? items[idx] : nil
        }
    }

    private func goNext() {
        guard currentIndex + 1 < items.count else { return }
        currentIndex += 1
    }

    private func goPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func revealControls() {
        showsControls.toggle()
    }
}
