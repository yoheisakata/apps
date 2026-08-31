import SwiftUI

/// `VideoLibraryView`の複数選択モードで使う一括操作(2026-08-28追加、「複数保存」
/// 「複数削除」という要望への対応)。呼び出し元の文脈によってボタンの意味が変わる ―
/// `SourceGridView`(OneDrive共有リンクを閲覧中)なら選択した動画をまとめてダウンロード、
/// `LocalDownloadsView`(「保存済み」一覧)なら選択した動画のローカルコピーをまとめて削除する。
enum LibrarySelectionAction {
    case download
    case delete
}

/// 動画一覧1画面ぶんの中身(表示形式(グリッド/リスト)・フォルダタブ・タグフィルター・
/// 複数選択・状態表示)を持つ、`videos`さえ渡せば動く再利用可能なビュー(2026-08-27追加、
/// 「ローカルに保存した動画の一覧もほしい」という要望への対応で`SourceGridView.swift`から
/// 切り出した ― 元々は`SourceGridView`が直接このロジックを持っていたが、「保存済み」一覧
/// (`LocalDownloadsView.swift`)にも全く同じUIが必要になったため共通化した)。
///
/// **フォルダタブは種類(TV/映画)フィルターから置き換えたもの**(2026-08-27、「アニメも
/// ドラマも、フォルダごとにタブにして」という要望への対応)。`video.channel`(共有フォルダ
/// 直下のサブフォルダ名、実際の物理フォルダ構造)をタブにする ― どんな命名規則の
/// ライブラリでも常に正しく分かれる。
///
/// **複数選択(2026-08-28追加、「ローカル保存を複数保存もつけてほしい。保存済み一覧からも
/// 1件削除、複数削除、全件削除を入れてほしい」という要望への対応)**: ツールバーの「選択」で
/// `isSelectionMode`に入ると、動画をタップしても再生せず選択のトグルになる
/// (mytube Mac版の`HomeVideosView`の複数選択モードと同じ発想)。選択中は上部に
/// 件数・すべて選択/解除・一括操作ボタン(`selectionAction`に応じて「ダウンロード」/
/// 「削除」)を出す。**「全件削除」はこのビューの複数選択とは別**(`LocalDownloadsView`側の
/// 専用ボタンで、選択操作を経ずに1タップでダウンロード済み全件を消せる ― 詳細は
/// `LocalDownloadsView.swift`参照)。
struct VideoLibraryView: View {
    let videos: [VideoItem]
    let isLoading: Bool
    let errorMessage: String?
    /// 1件も無いとき(読み込み中でもエラーでもない)に出すメッセージ。呼び出し元によって
    /// 意味が違う(「動画が見つかりませんでした」/「ダウンロード済みの動画はありません」)。
    let emptyMessage: String
    /// 動画をタップしたときに呼ぶ。第2引数は自動再生キュー ― タップ時点で`filteredVideos`
    /// (フォルダタブ・タグフィルター適用後)に表示されていた一覧をそのまま渡す。
    let onPlay: (VideoItem, [VideoItem]) -> Void
    let selectionAction: LibrarySelectionAction
    /// `true`なら`ConanContentKind.displayTitle(for:)`で番組名等を省略せず、
    /// `video.title`(ファイル名そのまま)を全文表示する(2026-08-28追加、「保存済みの
    /// 一覧では、ファイル名全部出して」という要望への対応)。`LocalDownloadsView`
    /// (「保存済み」一覧)は`true`、`SourceGridView`(OneDrive共有リンクの閲覧)は
    /// `false`(従来通り省略表示)を渡す ― 「保存済み」は複数の共有リンク・フォルダを
    /// 横断する一覧のため、どのファイルか一意に分かるようファイル名を省略しない方が
    /// 実用的と判断した。
    var showsFullTitle: Bool = false

    @State private var viewMode: HomeViewMode = Settings.homeViewMode
    /// `nil`なら「すべて」(全チャンネル合算)。
    @State private var selectedChannel: String?
    @State private var selectedTags: Set<String> = []
    @State private var showsUntaggedOnly = false

    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<VideoItem.ID> = []
    @State private var showsBulkDeleteConfirmation = false

    private let gridColumns = [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 10)]

    /// 実在するチャンネル(サブフォルダ)名、自然順(数字を含む場合はその大小)でソート
    /// (`0001-0799`→`0800-0899`のような範囲名フォルダが数値順に並ぶように)。
    private var availableChannels: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for video in videos where !seen.contains(video.channel) {
            seen.insert(video.channel)
            result.append(video.channel)
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// フォルダタブ適用後、タグフィルター適用前の母集団。タグフィルターの選択肢一覧
    /// (`availableTags`)もこれを参照する(適用後の`filteredVideos`から計算すると、
    /// タグを1つ選ぶたびに他の選択肢がボタンごと消えてしまうため ― mytube Mac版と同じ理由)。
    private var channelFilteredVideos: [VideoItem] {
        guard let selectedChannel else { return videos }
        return videos.filter { $0.channel == selectedChannel }
    }

    private var availableTags: [String] {
        let present = Set(channelFilteredVideos.flatMap { ConanEpisodeTags.allTags(for: $0.title) })
        guard !present.isEmpty else { return [] }
        let extraSorted = present.subtracting(ConanEpisodeTags.definedTagNames).sorted()
        return ConanEpisodeTags.definedTagNames.filter { present.contains($0) } + extraSorted
    }

    private var filteredVideos: [VideoItem] {
        var result = channelFilteredVideos
        if showsUntaggedOnly {
            result = result.filter { ConanEpisodeTags.allTags(for: $0.title).isEmpty }
        } else if !selectedTags.isEmpty {
            result = result.filter { !selectedTags.isDisjoint(with: Set(ConanEpisodeTags.allTags(for: $0.title))) }
        }
        return result
    }

    private var selectedVideos: [VideoItem] {
        filteredVideos.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isSelectionMode {
                    selectionToolbar
                    Divider()
                }
                // チャンネルが1つしか無ければタブ自体を出さない(「映画」共有リンクのように
                // サブフォルダを持たず全動画が「(ルート)」1本だけの場合、タブを出しても
                // 「すべて」と1個しかない選択肢が並ぶだけで意味が無いため)。
                if availableChannels.count > 1 {
                    ChannelTabRow(channels: availableChannels, selectedChannel: $selectedChannel)
                }
                if !availableTags.isEmpty {
                    TagFilterRow(availableTags: availableTags, selectedTags: $selectedTags, showsUntaggedOnly: $showsUntaggedOnly)
                }
                content
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(isSelectionMode ? "完了" : "選択") {
                    isSelectionMode.toggle()
                    if !isSelectionMode { selectedIDs.removeAll() }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Picker("表示形式", selection: $viewMode) {
                    ForEach(HomeViewMode.allCases) { mode in
                        Image(systemName: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
            }
        }
        .onChange(of: viewMode) { _, newValue in Settings.homeViewMode = newValue }
        .confirmationDialog(
            "選択した\(selectedIDs.count)件のローカルコピーを削除しますか?",
            isPresented: $showsBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                for video in selectedVideos {
                    DownloadStore.shared.deleteLocalCopy(for: video)
                }
                isSelectionMode = false
                selectedIDs.removeAll()
            }
        }
    }

    /// 選択モード中のツールバー ― 件数表示、すべて選択/解除、一括操作(ダウンロード/削除)。
    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Text(selectedIDs.isEmpty ? "動画を選択してください" : "\(selectedIDs.count)件選択中")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(selectedIDs.count == filteredVideos.count && !filteredVideos.isEmpty ? "すべて解除" : "すべて選択") {
                if selectedIDs.count == filteredVideos.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(filteredVideos.map(\.id))
                }
            }
            .font(.caption)
            .disabled(filteredVideos.isEmpty)

            switch selectionAction {
            case .download:
                Button {
                    for video in selectedVideos {
                        DownloadStore.shared.startDownloadIfNeeded(for: video)
                    }
                    isSelectionMode = false
                    selectedIDs.removeAll()
                } label: {
                    Label("ダウンロード(\(selectedIDs.count))", systemImage: "arrow.down.circle")
                }
                .font(.caption.weight(.semibold))
                .disabled(selectedIDs.isEmpty)
            case .delete:
                Button(role: .destructive) {
                    showsBulkDeleteConfirmation = true
                } label: {
                    Label("削除(\(selectedIDs.count))", systemImage: "trash")
                }
                .font(.caption.weight(.semibold))
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func toggleSelection(_ video: VideoItem) {
        if selectedIDs.contains(video.id) {
            selectedIDs.remove(video.id)
        } else {
            selectedIDs.insert(video.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !videos.isEmpty {
            switch viewMode {
            case .grid:
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(filteredVideos) { video in
                        Button {
                            if isSelectionMode {
                                toggleSelection(video)
                            } else {
                                onPlay(video, filteredVideos)
                            }
                        } label: {
                            VideoCardView(video: video, isSelectionMode: isSelectionMode, isSelected: selectedIDs.contains(video.id), showsFullTitle: showsFullTitle)
                        }
                        .buttonStyle(.plain)
                        .videoDownloadContextMenu(video: video)
                    }
                }
                .padding(16)
            case .list:
                LazyVStack(spacing: 0) {
                    ForEach(filteredVideos) { video in
                        Button {
                            if isSelectionMode {
                                toggleSelection(video)
                            } else {
                                onPlay(video, filteredVideos)
                            }
                        } label: {
                            VideoRowView(video: video, isSelectionMode: isSelectionMode, isSelected: selectedIDs.contains(video.id), showsFullTitle: showsFullTitle)
                        }
                        .buttonStyle(.plain)
                        .videoDownloadContextMenu(video: video)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        } else if isLoading {
            statusView(systemImage: "arrow.triangle.2.circlepath", message: "読み込み中…", showsProgress: true)
        } else if let errorMessage {
            statusView(systemImage: "exclamationmark.triangle", message: errorMessage, showsProgress: false)
        } else {
            statusView(systemImage: "film", message: emptyMessage, showsProgress: false)
        }
    }

    private func statusView(systemImage: String, message: String, showsProgress: Bool) -> some View {
        VStack(spacing: 12) {
            if showsProgress {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding(.top, 100)
        .frame(maxWidth: .infinity)
    }
}

/// フォルダ(チャンネル)タブ(2026-08-27追加)。`TagFilterRow`と似た見た目の横スクロール
/// するカプセルボタン列だが、こちらは単一選択(OR ではなく排他)― 「すべて」+実在する
/// チャンネル名を並べる。
private struct ChannelTabRow: View {
    let channels: [String]
    @Binding var selectedChannel: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabButton(title: "すべて", isSelected: selectedChannel == nil) { selectedChannel = nil }
                ForEach(channels, id: \.self) { channel in
                    tabButton(title: channel, isSelected: selectedChannel == channel) { selectedChannel = channel }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func tabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.15)))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

/// ローカルDL機能(2026-08-27追加、「Local DL機能追加してほしい」という要望への対応)の
/// 長押しメニュー。グリッド・リスト両方の動画ボタンに`.videoDownloadContextMenu(video:)`で
/// 適用する ― カード/行全体が再生用の`Button`のラベルになっているため、ダウンロード操作は
/// タップ(再生)と衝突しない長押しコンテキストメニューにした(1件だけの操作用 ―
/// 複数件は`VideoLibraryView`の複数選択モード、2026-08-28追加、参照)。「保存済み」一覧
/// (`LocalDownloadsView`)ではすべての動画が`.downloaded`状態のため、常に「ローカル
/// コピーを削除」だけが出る(このメニュー自体を出し分ける特別な分岐は不要)。
private extension View {
    func videoDownloadContextMenu(video: VideoItem) -> some View {
        contextMenu {
            switch DownloadStore.shared.state(for: video) {
            case .notDownloaded, .failed:
                Button {
                    DownloadStore.shared.startDownloadIfNeeded(for: video)
                } label: {
                    Label("ローカルにダウンロード", systemImage: "arrow.down.circle")
                }
            case .downloading:
                Button {
                    DownloadStore.shared.cancelDownload(for: video)
                } label: {
                    Label("ダウンロードをキャンセル", systemImage: "xmark.circle")
                }
            case .downloaded:
                Button(role: .destructive) {
                    DownloadStore.shared.deleteLocalCopy(for: video)
                } label: {
                    Label("ローカルコピーを削除", systemImage: "trash")
                }
            }
        }
    }
}

/// サムネイル左上に重ねるダウンロード状態バッジ(2026-08-27追加)。`.notDownloaded`は
/// 何も表示しない(状態を持たない動画がほとんどのため、常時何か出すと煩雑になる)。
private struct DownloadBadge: View {
    let state: DownloadStore.State

    var body: some View {
        switch state {
        case .notDownloaded:
            EmptyView()
        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.6)))
                .foregroundStyle(.white)
                .padding(6)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .padding(6)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .padding(6)
        }
    }
}

/// 選択モード中にサムネイル右上へ重ねる選択マーク(2026-08-28追加)。`DownloadBadge`
/// (左上)と重ならないよう右上に置く。
private struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85), isSelected ? Color.accentColor : Color.black.opacity(0.35))
            .padding(6)
    }
}

/// グリッド表示1枚ぶんのカード。サムネイルは`ThumbnailStore`から非同期取得する
/// (2026-08-27追加、以前はプレースホルダーアイコンのみだった)。
private struct VideoCardView: View {
    let video: VideoItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let showsFullTitle: Bool
    @State private var thumbnail: UIImage?
    @ObservedObject private var downloadStore = DownloadStore.shared

    private var tags: [String] { ConanEpisodeTags.allTags(for: video.title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.15))
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topLeading) {
                if !isSelectionMode {
                    DownloadBadge(state: downloadStore.state(for: video))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelectionMode {
                    SelectionBadge(isSelected: isSelected)
                }
            }
            .task(id: video.id) { await loadThumbnail() }

            Text(showsFullTitle ? video.title : ConanContentKind.displayTitle(for: video.title))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(showsFullTitle ? nil : 2)
                .multilineTextAlignment(.leading)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    RelatedTagsRow(tags: tags)
                }
            }

            HStack {
                Text(video.channel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let size = video.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadThumbnail() async {
        if let cached = ThumbnailStore.shared.cachedImage(for: video) {
            thumbnail = cached
            return
        }
        thumbnail = await ThumbnailStore.shared.image(for: video)
    }
}

/// リスト表示(ハイブリッドビューモード相当)1行ぶんの行。mytube(Mac版)の
/// `Views/VideoTableView.swift`の名前列(小さいサムネイル+タイトル)に近い見た目を、
/// iOSでは`Table`が無いため単純な`HStack`の行として実装している(2026-08-27追加)。
private struct VideoRowView: View {
    let video: VideoItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let showsFullTitle: Bool
    @ObservedObject private var downloadStore = DownloadStore.shared

    private var tags: [String] { ConanEpisodeTags.allTags(for: video.title) }

    var body: some View {
        HStack(spacing: 10) {
            // リスト(ハイブリッド)表示ではサムネイルを取得しない(2026-08-28追加、
            // 「ハイブリッドモードでサムネイル取得しなくて良い。パフォーマンスあがる?」
            // という要望への対応)。行数が多いライブラリ(数百話)をリスト表示すると、
            // スクロールのたびに`AVAssetImageGenerator`によるリモートURLへのフレーム
            // 取得が行の数だけ走り、ネットワーク・デコード負荷になっていた ―
            // プレースホルダーアイコンの固定表示に置き換えることで、この負荷を
            // まるごと無くした(グリッド表示側の`VideoCardView`は従来通りサムネイルを
            // 取得する ― グリッドは元々サムネイルが主役の表示形式のため対象外)。
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(white: 0.15))
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            // 2026-08-27、「フォルダ名を削除することで縦をせまくして、サムネイルも
            // 小さくできないか」という要望への対応 ― 88x50から一段階小さくした。
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .topLeading) {
                if !isSelectionMode {
                    DownloadBadge(state: downloadStore.state(for: video))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(showsFullTitle ? video.title : ConanContentKind.displayTitle(for: video.title))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(showsFullTitle ? nil : 2)
                    .multilineTextAlignment(.leading)
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        RelatedTagsRow(tags: tags)
                    }
                }
                // フォルダ名(`video.channel`)は2026-08-27に削除した(「フォルダ名を
                // 削除することで縦をせまくしたい」という要望への対応 ― 直前に追加した
                // 「(ルート)のときだけ隠す」対応から一歩進めて、ハイブリッド表示では
                // フォルダ名自体を常に出さない方針にした)。ファイルサイズだけ右端に残す。
                if let size = video.size {
                    HStack {
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)

            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
