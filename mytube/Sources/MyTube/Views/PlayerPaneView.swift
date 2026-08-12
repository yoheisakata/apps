import AppKit
import AVKit
import SwiftUI

/// メイン画面上部に常駐する動画プレイヤー。`ContentView`は`selectedVideo`が非nilの間だけ
/// このビューを表示し、その代わりに`HomeVideosView`(グリッド)を隠す(下記2026-08-06の
/// 変更参照) ― 「戻る」の代わりに右上の✕(`onClose`)でプレイヤー自体を閉じてグリッドへ戻る。
///
/// **グリッド常時表示 → 動画選択中は非表示、の変遷**: 2026-08-05に「YouTubeのように
/// 1ページにしたい」という要望で、独立した「視聴ページ」(`WatchView`、画面ごと切り替え)
/// から、常に見えている`HomeVideosView`の上にこのビューが現れる形へ変えた(視聴中でも
/// グリッドから別の動画を探せるようにするため)。その後2026-08-06、「Playerをできるだけ
/// 大きくしたい。YouTubeのように、次の動画リストは右に」という要望で右に`upNextList`
/// (次の動画)を追加した際は、いったん「グリッドは常に見えたままにしたい」という方針を
/// 維持したまま`upNextList`の高さをプレイヤーに合わせて収めていた。しかし「再生中は
/// 一旦Grid消したらどうなる?」「やってみて」という流れで実際に試した結果、グリッドを
/// 隠しても`playerArea`自体は大きくならない(横幅で頭打ちのため)一方、`upNextList`が
/// 画面下まで使えるようになりYouTubeの視聴ページに近づくと判断し、`ContentView`側で
/// 動画選択中は`HomeVideosView`を出さない方針に変更した(2026-08-05の「視聴中でもグリッド
/// から探せる」という前提は撤回 ― 動画を探すには`upNextList`を使うか、✕で閉じてグリッドへ
/// 戻る)。
///
/// `video` は選択中の動画が変わるたびに親から新しい値を受け取る。`ContentView`側は
/// `selectedVideo`(`video`パラメータ)を更新するだけでこのビューの型・位置は変えない
/// ため、SwiftUIは同一インスタンスとして扱い`@StateObject`の`engine`を保持し続ける
/// (＝別の動画に切り替えても`AVPlayer`インスタンスは使い回され、プレイヤー全体が
/// 再マウントされるちらつきが起きない)。
struct PlayerPaneView: View {
    let video: VideoItem
    let queue: [VideoItem]
    /// ミニプレーヤーモード(2026-08-07追加、「常に最前面表示のミニプレーヤーモード」という
    /// 要望への対応)。`ContentView`側の`@State`を直接束縛する ― トグルするとウィンドウ全体を
    /// 小さくして最前面固定にする必要があり(`ContentView.body`/`WindowLevelAccessor`参照)、
    /// このビュー単体では完結しないため`Binding`にしている。オンの間は`body`が`miniPlayerBody`
    /// (動画+最小限のボタンのみ)を返し、`metadataRow`/`upNextList`は描画しない ―
    /// `ContentView`側で`TopBarView`/`SidebarView`も隠すことと合わせて、ウィンドウ全体が
    /// 動画のサイズまで小さくなる(`.windowResizability(.contentSize)`がSwiftUI側の
    /// idealサイズの変化に window フレームを追従させる、`Main.swift`参照)。
    @Binding var isMiniPlayerMode: Bool
    let onSelect: (VideoItem) -> Void
    let onClose: () -> Void
    /// 再生失敗ポップアップの「再読み込み」ボタンから呼ばれる(OneDrive限定、下記 alert 参照)。
    let onRetry: (VideoItem) -> Void

    @StateObject private var engine = PlayerEngine()
    @ObservedObject private var downloadStore = DownloadStore.shared
    @State private var spacebarMonitor: Any?
    @State private var showsDeleteLocalCopyConfirmation = false
    @State private var deleteLocalCopyErrorMessage: String?
    /// `PlayerEngine.onError` で再生失敗を検知した際のメッセージ(非nilでポップアップ表示)。
    @State private var playbackErrorMessage: String?
    /// YouTubeの視聴ページにある「自動再生」トグルと同じもの。オフにすると、動画を最後まで
    /// 見ても`queue`の次の項目へは進まない(`Settings.autoplayEnabled`に永続化)。
    @State private var isAutoplayEnabled = Settings.autoplayEnabled

    var body: some View {
        Group {
            if isMiniPlayerMode {
                miniPlayerBody
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        playerArea
                        metadataRow
                    }

                    upNextList
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(16)
            }
        }
        .onAppear {
            engine.onError = { message in playbackErrorMessage = message }
            play(video)
            setupAutoplayNext()
            installSpacebarMonitor()
        }
        .onChange(of: video) { newValue in
            play(newValue)
            setupAutoplayNext()
        }
        .onChange(of: queue) { _ in
            // 動画自体は変わらずチャンネル選択などで`queue`(=次の動画候補)だけが変わった
            // 場合も、オートプレイ用クロージャが古い`queue`を捕まえたままにならないよう
            // 組み直す(`setupAutoplayNext()`のドキュメント参照)。
            setupAutoplayNext()
        }
        .onChange(of: downloadStore.state(for: video)) { newState in
            // YouTube動画はダウンロード完了(`.downloaded`)まで`play(_:)`が`engine.load`を
            // 呼ばずに待機している。ここでダウンロードの完了を検知して初めて再生を開始する。
            guard newState == .downloaded, video.remoteKind == .youtube else { return }
            play(video)
        }
        .onDisappear {
            engine.stop()
            removeSpacebarMonitor()
        }
        .confirmationDialog(
            "「\(video.title)」のローカルコピーをゴミ箱に移動しますか?(\(video.remoteKind?.displayName ?? "")の元動画は削除されません)",
            isPresented: $showsDeleteLocalCopyConfirmation,
            titleVisibility: .visible
        ) {
            Button("ゴミ箱に移動", role: .destructive, action: deleteLocalCopy)
            Button("キャンセル", role: .cancel) {}
        }
        .alert(
            "削除できませんでした",
            isPresented: Binding(get: { deleteLocalCopyErrorMessage != nil }, set: { if !$0 { deleteLocalCopyErrorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(deleteLocalCopyErrorMessage ?? "")
        }
        .alert(
            "再生できませんでした",
            isPresented: Binding(get: { playbackErrorMessage != nil }, set: { if !$0 { playbackErrorMessage = nil } })
        ) {
            // OneDriveは署名付きURLの期限切れが失敗の主な原因のため、再スキャンで直せる
            // 見込みがある。YouTubeはダウンロード失敗が原因で再スキャンでは直らないため出さない
            // (`ContentView.retryPlayback(for:)`もOneDrive以外は無視する)。
            if video.remoteKind == .oneDrive {
                Button("再読み込み") { onRetry(video) }
            }
            Button("OK") {}
        } message: {
            Text(playbackErrorMessage ?? "")
        }
    }

    /// 動画本体。当初(2026-08-05)はタイトル等の情報を右の`infoSidebar`(固定幅280→220pt)へ
    /// 追い出して`maxHeight`を420→560→720と拡大したが、2026-08-06に「次の動画リストを
    /// YouTubeのように右に」という要望で`infoSidebar`は`metadataRow`(下記、プレイヤーの下)に
    /// 置き換わり、右列は`upNextList`(次の動画)専用になった。タイトル等が横幅を取り合わなく
    /// なった分、`playerArea`の実質的な横幅の取り分はさらに広がっている。
    private var playerArea: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                NativeVideoPlayerView(player: engine.player)
                    // 動画を切り替えるたびに AVKit 側のネイティブ再生ビューを強制的に作り直す。
                    // `.id()` を付けないと、`replaceCurrentItem` 後も古い動画のフレームが
                    // 画面に残ったまま更新されない(タイトル等の表示は新しい動画に切り替わって
                    // いるのに、実際の映像だけ前の動画のまま、という AVKit-SwiftUI ブリッジ側の
                    // 表示崩れが起きることがある)。
                    .id(video.id)

                // YouTube動画はダウンロード完了まで`PlayerEngine`にURLを渡さない
                // (`play(_:)`参照 ― 映像+音声が別ストリームでAVPlayerでは合成再生できない
                // ため、OneDriveと違い即時ストリーミングできない)。その間は真っ黒な
                // プレイヤー領域の上に進捗を重ねて表示する。
                if video.remoteKind == .youtube, !downloadStore.isDownloaded(video) {
                    YouTubeDownloadingOverlay(state: downloadStore.state(for: video))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // グリッドの上に常駐するプレイヤーを閉じるボタン(以前の「戻る」に相当)。
            // ミニプレーヤーへ入るボタンは`TopBarView`側(`ContentView.onEnterMiniPlayer`)に
            // 移した(2026-08-07、「トップバーにボタンをおいて」という要望への対応 ―
            // 以前はここに`pip.enter`ボタンを重ねていたが、動画上に小さいアイコンを置くより
            // 常時見えるトップバーの方が見つけやすいと判断し、こちらは元の1ボタンに戻した)。
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("プレイヤーを閉じる")
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 720)
    }

    /// ミニプレーヤーモード中の`body`(動画本体のみ、`playerArea`/`metadataRow`/`upNextList`は
    /// 描画しない)。`ContentView`側の`.windowResizability(.contentSize)`がウィンドウを
    /// このビューのidealサイズまで自動的に縮める(`isMiniPlayerMode`のドキュメント参照)。
    /// `engine`/オートプレイの状態は`PlayerPaneView`自体が破棄されないため(`@StateObject`)
    /// 通常モードとの往復で失われない。
    /// **サイズ変更可能**(2026-08-07、「ミニプレーヤーのサイズは変更可能に」という要望への
    /// 対応): 以前は`.frame(width: 360)`で固定していた(＝`.windowResizability(.contentSize)`
    /// が導出するウィンドウの最小/最大サイズも360固定になり、ドラッグでのリサイズができな
    /// かった)ため、`minWidth`/`idealWidth`/`maxWidth`の範囲を持つ`.frame`に変え、範囲内で
    /// ウィンドウ端をドラッグしてリサイズできるようにした。16:9比を保ったまま伸縮する見た目は
    /// `.aspectRatio(16/9, contentMode: .fit)`(SwiftUI側、ウィンドウサイズが変わるたびに
    /// 再計算される)だけに任せている ― 当初は`ContentView.WindowLevelAccessor`が
    /// `NSWindow.contentAspectRatio`も16:9に固定してドラッグ中の一瞬の黒帯を防いでいたが、
    /// ①ネイティブzoomアニメーションとの組み合わせでクラッシュする、②通常モードに戻っても
    /// 解除しきれずドラッグリサイズで高さが縮み続ける、という2つの実機不具合が出たため撤去した
    /// (`WindowLevelAccessor`のドキュメント参照)。
    private var miniPlayerBody: some View {
        ZStack(alignment: .topTrailing) {
            NativeVideoPlayerView(player: engine.player)
                .id(video.id)

            // ミニプレーヤーを終了して元のサイズへ戻るボタン(2026-08-07)。実際に元のウィンドウ
            // サイズへ戻す処理自体は`ContentView.WindowLevelAccessor`が退避しておいたフレームを
            // 使って行う(このビュー側は`isMiniPlayerMode = false`にするだけ)。アイコンは
            // 「拡大して戻す」を表す矢印(`arrow.up.left.and.arrow.down.right`)を使う ―
            // 当初`plus.circle.fill`だったが、動画の上に重ねると「+」は視認しづらく、
            // 隣の✕(閉じる)とも見分けにくいという指摘を受けて変更した。この矢印アイコン自体は
            // 円形の背景を持たない単層シンボルのため、✕ボタン側の`xmark.circle.fill`と
            // 見た目を揃えるための黒背景の円を`.background(Circle())`で自前描画している
            // (`xmark.circle.fill`のような`X.circle.fill`という名前のバリアントが存在するか
            // 確証が持てなかったため、シンボル名に依存せず確実に同じ見た目を作れるこちらを選んだ)。
            HStack(spacing: 8) {
                Button {
                    isMiniPlayerMode = false
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .help("元のサイズに戻る")

                Button {
                    isMiniPlayerMode = false
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("プレイヤーを閉じる")
            }
            .padding(6)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black)
        .frame(minWidth: 240, idealWidth: 360, maxWidth: 960)
    }

    /// プレイヤーの下に横一列で並ぶ、タイトル・チャンネル・ダウンロード状態・自動再生トグル・
    /// 再生速度メニュー(2026-08-06、`upNextList`の追加に伴い右の縦積み`infoSidebar`から
    /// この位置へ戻した ― 右列は次の動画リスト専用にするため。プレイヤーと同じ横幅を
    /// 使えるので、280/220pt幅に収める必要があった頃と違い1行のHStackで余裕がある)。
    private var metadataRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.title3.bold())
                .lineLimit(2)

            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text(video.channel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let modified = video.modifiedDate {
                    Text("・")
                        .foregroundStyle(.secondary)
                    Text(modified, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if video.remoteKind == .oneDrive {
                    // OneDriveはダウンロードが自動で始まらないため、状態表示だけの
                    // `DownloadStatusLabel`ではなくON/OFFを操作できる`LocalSaveToggle`を使う
                    // (`play(_:)`のドキュメント参照)。
                    LocalSaveToggle(video: video)
                } else if video.isRemote {
                    DownloadStatusLabel(state: downloadStore.state(for: video), fileSize: downloadStore.localFileSize(for: video)) {
                        showsDeleteLocalCopyConfirmation = true
                    }
                }
                Spacer(minLength: 12)
                Toggle("自動再生", isOn: $isAutoplayEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: isAutoplayEnabled) { newValue in
                        Settings.autoplayEnabled = newValue
                        setupAutoplayNext()
                    }
                PlaybackSpeedMenu(engine: engine)
            }
        }
    }

    /// 「次の動画」リスト(2026-08-06追加、「Playerをできるだけ大きくしたい。YouTubeのように、
    /// 次の動画リストは右に」という要望への対応)。`queue`(オートプレイのキューと同じ、
    /// `filteredVideos`由来)のうち現在の`video`より後ろの項目をサムネイル付きの縦リストで
    /// 表示し、クリックで`onSelect`を呼んで即座にその動画へ切り替える。
    /// **高さは画面下まで伸ばす**(`.frame(maxHeight: .infinity)`)。当初は`playerArea`+
    /// `metadataRow`の実測高さに合わせて収めていた(`GeometryReader`+`PreferenceKey`で測定
    /// ― 「画面下までストレッチすると`HomeVideosView`のグリッドが実質見えなくなる」ことを
    /// 理由に、その頃はグリッドを常に見せる方針だったため)が、2026-08-06に`ContentView`側で
    /// 「動画選択中はグリッドを表示しない」方針へ変更した(`PlayerPaneView`冒頭のドキュメント
    /// 参照)のに伴い、その制約が無くなったため素直に画面下まで伸ばす形に単純化した。
    private var upNextList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !upNextVideos.isEmpty {
                Text("次の動画")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(upNextVideos) { nextVideo in
                        UpNextRow(video: nextVideo) { onSelect(nextVideo) }
                    }
                }
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// `queue`のうち現在の`video`より後ろの項目だけ(YouTubeの「次の動画」と同じく、
    /// 既に見終わった/現在見ている項目は出さない)。`video`が`queue`に見つからない場合
    /// (絞り込みが変わった直後など)は`queue`全体をそのまま「次の動画」として出す。
    private var upNextVideos: [VideoItem] {
        guard let index = queue.firstIndex(of: video) else { return queue }
        return Array(queue[(index + 1)...])
    }

    private func deleteLocalCopy() {
        Task {
            do {
                try await downloadStore.deleteLocalCopy(for: video)
            } catch {
                deleteLocalCopyErrorMessage = error.localizedDescription
            }
        }
    }

    /// OneDriveはローカルにダウンロード済みならそちらを優先して再生し(`DownloadStore.playableURL`)、
    /// まだなら再生自体はストリーミングで即座に始まる。**ダウンロードは自動では始めない**
    /// (2026-08-05、「OneDriveの場合はローカルに保存はトグルにする」という要望への対応 ―
    /// 以前は再生開始のたびに`startDownloadIfNeeded`を無条件で呼んでいたが、今は`Views/
    /// LocalSaveToggle.swift`のトグルをONにしたときだけ`DownloadStore`が呼ばれる。既に
    /// トグルがONで進行中/完了済みのダウンロードがある場合も、それは`DownloadStore.state`側で
    /// 引き続き管理されるため、ここで何もしなくても状態は失われない)。**YouTubeは違う**:
    /// 映像+音声が別ストリームでAVPlayerでは合成再生できないため、`.downloaded`になるまで
    /// `engine.load`を呼ばない(`onChange(of: downloadStore.state(for: video))`がダウンロード
    /// 完了を検知してこのメソッドを呼び直す)― YouTubeは引き続きダウンロードが必須なので
    /// 自動で開始する。
    private func play(_ video: VideoItem) {
        if video.remoteKind == .youtube, !downloadStore.isDownloaded(video) {
            engine.stop()
            downloadStore.startDownloadIfNeeded(for: video)
            return
        }
        engine.load(url: downloadStore.playableURL(for: video))
        if video.remoteKind == .youtube {
            downloadStore.startDownloadIfNeeded(for: video)
        }
    }

    /// スペースキーで再生/一時停止する。`AVPlayerView` 自体もスペースキーに反応する仕様だが、
    /// それはビュー自身(またはその子)が first responder のときだけで、検索欄にフォーカスが
    /// 残っている等の理由で効かないことがある。フォーカス状態に関わらず確実に動くよう、
    /// プレイヤーが表示されている間だけアプリ全体のキーイベントをローカルモニターで監視する。
    /// テキストフィールド編集中はスペース入力を奪わないよう、firstResponder がテキスト編集系
    /// (`NSText`)なら素通しする。
    private func installSpacebarMonitor() {
        guard spacebarMonitor == nil else { return }
        spacebarMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49 else { return event }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
                return event
            }
            engine.togglePlayPause()
            return nil
        }
    }

    private func removeSpacebarMonitor() {
        if let spacebarMonitor {
            NSEvent.removeMonitor(spacebarMonitor)
        }
        spacebarMonitor = nil
    }

    /// 現在の `video`/`queue`/`isAutoplayEnabled` を捕捉したクロージャを組み直す。動画切り替え時
    /// (`onAppear`/`onChange(of: video)`)、動画は変わらず`queue`だけが変わった場合
    /// (`onChange(of: queue)` ― 再生中にサイドバーでチャンネルを切り替えた場合など)、
    /// 「自動再生」トグルが変わった場合(`onChange(of: isAutoplayEnabled)`)のいずれでも
    /// 呼び直すことで、常に最新の状態を参照する(`PlayerPaneView`は構造体のため、クロージャは
    /// 作成時点の値をそのまま捕捉する ― 後から`isAutoplayEnabled`だけ変えても、組み直さない
    /// 限りクロージャ内の値は古いまま)。
    private func setupAutoplayNext() {
        engine.onFinished = {
            guard isAutoplayEnabled else { return }
            guard let index = queue.firstIndex(of: video), index + 1 < queue.count else { return }
            onSelect(queue[index + 1])
        }
    }
}

/// 動画情報行に出すダウンロード状態の表示。`.notDownloaded`/`.failed`は
/// 何も表示しない(失敗は次に再生した際に`DownloadStore.startDownloadIfNeeded`が
/// 自動的に再試行するため、常時表示のエラーUIは設けていない)。
private struct DownloadStatusLabel: View {
    let state: DownloadStore.State
    /// ダウンロード済みのローカルコピーの実際のファイルサイズ(2026-08-05追加、「ローカルにDLした
    /// サイズを各ビデオに表示してほしい」という要望への対応)。`nil`ならサイズ無しで表示する。
    var fileSize: Int64? = nil
    let onDelete: () -> Void

    private var downloadedLabel: String {
        guard let fileSize else { return "ローカルに保存済み" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "ローカルに保存済み(\(formatter.string(fromByteCount: fileSize)))"
    }

    var body: some View {
        switch state {
        case .notDownloaded, .failed:
            EmptyView()
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView(value: progress)
                    .frame(width: 40)
                Text("ローカルに保存中…")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        case .downloaded:
            HStack(spacing: 4) {
                Label(downloadedLabel, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("ローカルコピーを削除")
            }
        }
    }
}

/// YouTube動画がダウンロード完了(再生可能)になるまでプレイヤー領域に重ねる表示。
/// `.notDownloaded`は`play(_:)`が`startDownloadIfNeeded`を呼んだ直後の一瞬だけ経由する状態
/// (`states`への書き込みが`.downloading(progress: 0)`に切り替わるまでのラグ)なので、
/// こちらも進捗0%の準備中として表示する。
private struct YouTubeDownloadingOverlay: View {
    let state: DownloadStore.State

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: progressValue)
                .frame(width: 160)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var progressValue: Double {
        if case .downloading(let progress) = state { return progress }
        return 0
    }

    private var label: String {
        switch state {
        case .failed(let message):
            return "ダウンロードに失敗しました: \(message)"
        case .downloading(let progress):
            return "動画を取得中… \(Int(progress * 100))%"
        case .notDownloaded, .downloaded:
            return "動画を取得中…"
        }
    }
}

/// `upNextList`の1行(2026-08-06追加)。小さいサムネイル(`VideoThumbnailView`、長さ・
/// ダウンロード状態バッジ込み)+タイトル(2行)+チャンネル名。`VideoCardView`と同じく
/// カード全体を`Button`で覆う単純な作り(ネストした別コントロールは持たないため、
/// `Views/PointingHandCursor.swift`が警告する「`Button`内側のインタラクティブなコントロール」
/// 問題は該当しない)。
private struct UpNextRow: View {
    let video: VideoItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                VideoThumbnailView(video: video, width: 120)
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(video.channel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
    }
}
