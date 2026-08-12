import SwiftUI

/// YouTube のヘッダーを模した、常時表示の上部バー。ロゴ・検索欄・フォルダ選択ボタンを持つ。
struct TopBarView: View {
    @Binding var searchText: String
    @Binding var selectedSortOption: SortOption
    @Binding var homeViewMode: HomeViewMode
    @Binding var minLengthSecondsText: String
    @Binding var maxLengthSecondsText: String
    /// 左のフォルダツリーサイドバーを隠しているかどうか(2026-08-06追加、「再生プレーヤーの
    /// 下のリストを削除したら、画面がもう少し大きくなるのでは?」という提案を受けて ―
    /// 実際にはプレイヤーは横幅で頭打ちになっていたため、下のグリッドではなくこのサイドバーを
    /// 隠す方が効く。動画を開くと`ContentView`が自動でこれを`true`にする(下記参照)ため、
    /// この左端のボタンは主に「動画視聴中でもフォルダを切り替えたい」ときの手動復帰用。
    @Binding var isSidebarCollapsed: Bool
    let isMeasuringDurations: Bool
    let onChooseFolder: () -> Void
    let onOpenShareLink: () -> Void
    let onOpenYouTubePlaylist: () -> Void
    /// 左上の「MyTube」ロゴを押したときのアクション(2026-08-06追加、「一番左上のMyTube
    /// アイコンを押したら、起動直後のPlayerの無い画面(ホーム画面)に戻りたい」という
    /// 要望への対応)。`ContentView`が`selectedVideo = nil`を渡す ― YouTubeのロゴクリックと
    /// 同じ「ホームへ戻る」操作。
    let onGoHome: () -> Void
    /// ミニプレーヤーへ入るボタンの有効/無効(動画再生中のみ)とアクション(2026-08-07追加、
    /// 「トップバーにボタンをおいて」という要望への対応 ― 以前は動画プレイヤー右上に
    /// `pip.enter`アイコンを重ねていたが、常時見えるトップバーの方が見つけやすいためこちらへ
    /// 移した。ミニプレーヤーから元に戻すボタンは逆にトップバーが隠れているため出せず、
    /// `PlayerPaneView`の`miniPlayerBody`側(＋ボタン)に残っている)。
    let isMiniPlayerAvailable: Bool
    let onEnterMiniPlayer: () -> Void

    @State private var showsLengthFilterPopover = false
    @State private var showsCacheSettingsPopover = false
    @State private var showsDeleteCacheConfirmation = false
    @State private var cacheSummary: (count: Int, totalBytes: Int64) = (0, 0)
    @State private var isDeletingCache = false
    @State private var deleteCacheErrorMessage: String?
    /// `Settings.maxCacheBytes`(バイト)をGB単位のテキストとして編集する
    /// (2026-08-05追加、`CacheSettingsPopover`参照)。
    @State private var maxCacheGBText: String = String(Settings.maxCacheBytes / 1_000_000_000)

    private var isLengthFilterActive: Bool {
        !minLengthSecondsText.isEmpty || !maxLengthSecondsText.isEmpty
    }

    private var cacheSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: cacheSummary.totalBytes)
    }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                isSidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help(isSidebarCollapsed ? "サイドバーを表示" : "サイドバーを隠す")

            Button(action: onEnterMiniPlayer) {
                Image(systemName: "pip.enter")
            }
            .disabled(!isMiniPlayerAvailable)
            .help("ミニプレーヤー")

            Button(action: onGoHome) {
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(.red)
                    Text("MyTube")
                        .font(.title3.bold())
                }
            }
            .buttonStyle(.plain)
            .help("ホームに戻る")

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("動画を検索", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 420)

            Spacer(minLength: 12)

            // グリッド/一覧/ハイブリッドの表示形式切り替え(2026-08-05追加、「MyTubeの動画の
            // 表示の仕方を増やしたい」という要望への対応)。Finderの表示形式ボタンと同じ、
            // アイコンだけのセグメントピッカー。
            Picker("表示形式", selection: $homeViewMode) {
                ForEach(HomeViewMode.allCases) { mode in
                    Image(systemName: mode.systemImage)
                        .help(mode.label)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)

            Menu {
                ForEach(SortOption.allCases) { option in
                    Button {
                        selectedSortOption = option
                    } label: {
                        if option == selectedSortOption {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Label(selectedSortOption.label, systemImage: "arrow.up.arrow.down")
            }

            Button {
                showsLengthFilterPopover = true
            } label: {
                Label("長さ", systemImage: isLengthFilterActive ? "timer.circle.fill" : "timer")
            }
            .popover(isPresented: $showsLengthFilterPopover) {
                LengthFilterPopover(
                    minSecondsText: $minLengthSecondsText,
                    maxSecondsText: $maxLengthSecondsText,
                    isMeasuring: isMeasuringDurations
                )
            }

            Button(action: onChooseFolder) {
                Label("ローカル", systemImage: "folder.badge.plus")
            }
            Button(action: onOpenYouTubePlaylist) {
                Label("Youtube Playlist", systemImage: "play.rectangle.fill")
            }
            Button(action: onOpenShareLink) {
                Label("OneDrive Link", systemImage: "link")
            }

            Button {
                cacheSummary = DownloadStore.shared.localCacheSummary()
                showsCacheSettingsPopover = true
            } label: {
                Label("キャッシュ", systemImage: "internaldrive")
            }
            .popover(isPresented: $showsCacheSettingsPopover) {
                CacheSettingsPopover(
                    totalBytes: cacheSummary.totalBytes,
                    fileCount: cacheSummary.count,
                    maxCacheGBText: $maxCacheGBText,
                    onDeleteAll: {
                        showsCacheSettingsPopover = false
                        showsDeleteCacheConfirmation = true
                    },
                    isDeleting: isDeletingCache
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onChange(of: maxCacheGBText) { newValue in
            guard let gb = Int64(newValue), gb > 0 else { return }
            Settings.maxCacheBytes = gb * 1_000_000_000
            DownloadStore.shared.enforceCacheLimit()
        }
        .confirmationDialog(
            cacheSummary.count > 0
                ? "ローカルにダウンロードした\(cacheSummary.count)件(\(cacheSizeText))を一気に削除しますか?(OneDrive/YouTube上の元動画には影響しません)"
                : "削除するローカルキャッシュはありません",
            isPresented: $showsDeleteCacheConfirmation,
            titleVisibility: .visible
        ) {
            if cacheSummary.count > 0 {
                Button("すべて削除", role: .destructive, action: deleteAllCache)
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert(
            "削除できませんでした",
            isPresented: Binding(get: { deleteCacheErrorMessage != nil }, set: { if !$0 { deleteCacheErrorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(deleteCacheErrorMessage ?? "")
        }
    }

    /// OneDrive/YouTubeのダウンロード済みローカルコピーを一気にゴミ箱へ移動する
    /// (2026-08-05追加、「ローカルにDLしたキャッシュを一気に削除する機能」という要望への対応)。
    /// `DownloadStore.shared`を直接呼ぶ ― `VideoCardView`/`PlayerPaneView`の個別削除と同じ方針で、
    /// `ContentView`にこの操作のための状態を持たせる必要はない。
    private func deleteAllCache() {
        isDeletingCache = true
        Task {
            do {
                try await DownloadStore.shared.deleteAllLocalCopies()
            } catch {
                deleteCacheErrorMessage = error.localizedDescription
            }
            isDeletingCache = false
        }
    }
}
