import SwiftUI

/// ハイブリッド型(一覧表示、2026-08-05追加。当初はグリッド/一覧/ハイブリッドの3種類が
/// あり、一覧=サムネイル無しのファイル名一覧、ハイブリッド=小さいサムネイル+ファイル名の
/// `LazyVStack`という別々の実装だったが、「Finderのように見やすくしてほしい」→
/// 「ハイブリッド表示も一覧と同様に見やすくして」という2段階の要望を受けて共通の`Table`
/// (AppKitの`NSTableView`をラップしたSwiftUI標準コンポーネント)ベースの表形式に統合 →
/// 統合の結果ほぼ同じ見た目になった一覧型は「一覧は削除します」という要望で廃止し、
/// このハイブリッド型(小さいサムネイル付き)だけが残った)。名前(小さいサムネイル+
/// ファイル名)・長さ・サイズ(2026-08-14追加)・ソース(ローカル/OneDrive/YouTube)・
/// チャンネルの5列を`TableColumn`で
/// 定義するだけで、ヘッダー行・交互の背景色・選択ハイライトといったFinderのリスト表示
/// そのものの見た目がSwiftUI側から自動的に得られる(独自にストライプ背景等を描画する必要は
/// ない)。**`Table`自体がスクロール可能な`NSScrollView`を内包する**ため、`HomeVideosView`側
/// ではこれを`ScrollView`に入れ子にしない(二重スクロールになり操作感が壊れるため ―
/// `HomeVideosView.body`参照)。
struct VideoTableView: View {
    let videos: [VideoItem]
    let onSelect: (VideoItem) -> Void
    /// 複数選択モード(2026-08-21追加)。オンの間は行クリックが再生ではなく選択トグルになる ―
    /// `HomeVideosView`の項参照。
    var isSelectionMode: Bool = false
    var selectedIDs: Set<VideoItem.ID> = []
    var onToggleSelect: (VideoItem) -> Void = { _ in }
    var onDeleteLocal: ((VideoItem) async throws -> Void)? = nil

    /// `Table`標準の単一選択。選択モード中は行を選ぶたびに`onToggleSelect`へ振り替えてから
    /// 即座に`nil`へ戻す(同じ行を連続でチェックON/OFFできるようにするため ― `onChange`は
    /// 値が変化したときしか発火しないので、選択状態を保持したままだと2回目のクリックが
    /// 拾えない)。Finder本来の「選択してから別操作」というワークフローは持たず、選択即
    /// 再生のトリガーとして使うだけなので、選択モードでない間は複数選択のUIも不要。
    @State private var selection: VideoItem.ID?
    /// ヘッダークリックでのソート(2026-08-14追加、「動画リスト表示でヘッダーをクリックしたら
    /// ソートしてほしい。ソート機能は一覧のみでヘッダークリックでできるようにして」という
    /// 要望への対応 ― 以前あった`TopBarView`の「並び替え」メニュー(`SortOption`)はこの機能に
    /// 一本化する形で撤去済み、グリッド表示はファイル名昇順の固定順になった)。`Table`標準の
    /// `sortOrder`機構(クリックで矢印が出て並び替わる、ネイティブのFinder風挙動)をそのまま使う。
    @State private var sortOrder: [KeyPathComparator<Row>] = [KeyPathComparator(\.title)]
    /// 「サイズ」列のソートを正しく保つための先読み結果(2026-08-21追加、「サイズのソートが
    /// おかしい」というユーザー報告への対応)。以前は`SizeCell`が可視セルだけを個別に
    /// (セル内に閉じた`@State`で)非同期取得しており、値が届いても`rows`(＝ソート結果)を
    /// 再計算させる手段が無かった ― 画面外でまだ一度もセルが表示されていない動画は
    /// `fileSizeSortKey`が常に`.max`扱いのままで、ソートしてもほとんどの行が「サイズ不明」
    /// として束ねられ、ソート自体が効いていないように見えていた。この`@State`を
    /// `VideoTableView`自身が持つことで、`loadFileSizes()`が値を書き込むたびに`body`が
    /// 再評価されて`rows`が正しい順序に更新される(`FileSizeStore.limiter`が大きい
    /// ライブラリでも一斉に大量のファイルI/Oが走らないよう絞っている)。
    @State private var fileSizes: [VideoItem.ID: Int64] = [:]

    /// `Table`の`sortUsing:`は`KeyPathComparator`(値がその場で`Comparable`である必要がある)
    /// を要求するため、`VideoItem`をそのまま渡さずこの薄いラッパーに変換してから`Table`に渡す
    /// ― `video.remoteKind`(enum)は`Comparable`ではないため`sourceLabel`という文字列に、
    /// `duration`(長さ、`VideoItem`自体は保持せず`ThumbnailStore`のキャッシュから同期的に
    /// 引く)は`Optional<TimeInterval>`をこのファイル内で`Comparable`にした上で保持する。
    private struct Row: Identifiable {
        let video: VideoItem
        /// `fileSize`と違い`duration`は今のところソートの不具合が報告されていないため
        /// (`ContentView.ensureDurationsLoaded()`が長さフィルター有効時に全動画分を先読みし、
        /// その結果が`ContentView`の`@State`更新経由で`VideoTableView`の再描画・再ソートを
        /// 間接的に誘発するため、実用上は問題が顕在化しにくい)、`fileSize`のような
        /// `VideoTableView`側の明示的な先読み`@State`へはまだ移していない。
        var duration: TimeInterval? {
            video.knownDurationSeconds ?? MainActor.assumeIsolated { ThumbnailStore.shared.cachedDuration(for: video) }
        }
        /// `VideoTableView.fileSizes`(先読み結果)からこの行の初期化時に渡される。
        let fileSize: Int64?

        var id: VideoItem.ID { video.id }
        var title: String { video.title }
        var channel: String { video.channel }
        var sourceLabel: String { video.remoteKind?.displayName ?? "ローカル" }

        /// `KeyPathComparator`にそのまま渡せる非Optional版(2026-08-14追加)。`TimeInterval?`に
        /// `Comparable`適合(下記`extension Optional`)を追加して直接渡すと、`Table`の
        /// 結果ビルダーの型検査がクラッシュする不具合(実機で確認、"failed to produce
        /// diagnostic"というコンパイラ内部エラー)があったため、代わりにこの非Optionalな
        /// キーを使う ― 長さ不明の動画は`.greatestFiniteMagnitude`(最大値)を返し、
        /// 昇順ソート時に自然と末尾へ回る(降順時は先頭に来る点だけ`nil`の厳密な「常に末尾」
        /// 規約とは異なるが、実用上の影響は小さいため許容している)。
        var durationSortKey: TimeInterval { duration ?? .greatestFiniteMagnitude }

        /// 「サイズ」列(2026-08-14追加、「ハイブリッド表示のときは動画のサイズをカラムで
        /// 表示して」という要望への対応)。`Int64.max`を未取得時のフォールバックにする
        /// (昇順ソートで自然と末尾に回る)。
        var fileSizeSortKey: Int64 { fileSize ?? .max }
    }

    private var rows: [Row] {
        videos.map { video in
            Row(video: video, fileSize: fileSizes[video.id] ?? MainActor.assumeIsolated { FileSizeStore.shared.cachedSize(for: video) })
        }.sorted(using: sortOrder)
    }

    /// 表示中の全動画ぶんのファイルサイズを一斉に先読みし、`fileSizes`へ書き戻す。
    /// `.task(id: videos)`から呼ばれる ― `videos`(表示中の一覧)が変わるたびに前回の
    /// タスクは自動キャンセルされ、ビューが画面から消えたときも自動キャンセルされる
    /// (SwiftUIの`.task`のライフサイクルにそのまま乗るため、`ContentView.
    /// ensureDurationsLoaded()`のような手動の`Task.detached`管理は不要)。
    /// **`fileSizes`への書き戻しは結果が揃うまでまとめて1回だけ行う**(2026-08-21修正、
    /// 「ハイブリッドモードで、ソートしたあと、再生できない」というユーザー報告への対応)。
    /// 以前は`for await`ループの中で1件解決するたびに`fileSizes[id] = size`していたため、
    /// 「サイズ」列でソート中は届いた値のたびに`rows`が再計算されて`Table`の行が並び替わり
    /// 続けていた ― 特にサイズ列をソートした直後は多くの動画がまだ`.max`(未取得)扱いで
    /// 一斉に結果が届く期間と重なりやすく、ユーザーが行をクリックした瞬間に`Table`側で
    /// 行の入れ替え(`NSTableView`の`reloadData`)が起きてクリックが正しい行の選択として
    /// 成立しないことがあった(クリックしても`selection`が更新されず、再生が始まらない)。
    /// 全結果をローカル変数`collected`に集めてから`fileSizes.merge(_:uniquingKeysWith:)`で
    /// 1回だけ書き戻すことで、この先読み1回につき`rows`の再計算・`Table`の再描画も1回に
    /// 抑え、ロード中に行が動き続けてクリックを妨げることがないようにした(トレードオフ:
    /// 以前のように1件ずつサイズが埋まっていく体感は無くなり、先読みが完了するまで対象の
    /// セルは「—」のまま。`FileSizeStore.limiter`(8並列)のおかげで通常のライブラリ規模なら
    /// 数秒以内に揃う)。
    private func loadFileSizes() async {
        let missing = videos.filter { fileSizes[$0.id] == nil }
        guard !missing.isEmpty else { return }
        var collected: [VideoItem.ID: Int64] = [:]
        await withTaskGroup(of: (VideoItem.ID, Int64?).self) { group in
            for video in missing {
                group.addTask {
                    (video.id, await FileSizeStore.shared.loadSize(for: video))
                }
            }
            for await (id, size) in group {
                guard let size else { continue }
                collected[id] = size
            }
        }
        guard !collected.isEmpty else { return }
        fileSizes.merge(collected) { _, new in new }
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("名前", sortUsing: KeyPathComparator(\.title)) { row in
                NameCell(
                    video: row.video,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedIDs.contains(row.video.id),
                    onToggleSelect: onToggleSelect,
                    onDeleteLocal: onDeleteLocal
                )
            }
            .width(min: 280, ideal: 520)

            TableColumn("長さ", sortUsing: KeyPathComparator(\.durationSortKey)) { row in
                DurationCell(video: row.video)
            }
            .width(min: 56, ideal: 64)

            TableColumn("サイズ", sortUsing: KeyPathComparator(\.fileSizeSortKey)) { row in
                SizeCell(fileSize: row.fileSize)
            }
            .width(min: 64, ideal: 80)

            TableColumn("ソース", sortUsing: KeyPathComparator(\.sourceLabel)) { row in
                Text(row.sourceLabel)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("チャンネル", sortUsing: KeyPathComparator(\.channel)) { row in
                Text(row.channel)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
        }
        // 単一クリックで即再生する(グリッド型と同じ「1クリックで開く」操作感に揃えるため ―
        // Finder本来の「シングルクリックで選択・ダブルクリックで開く」とはあえて違えている)。
        // 選択後は`ContentView`側で`selectedVideo`が非nilになり`HomeVideosView`自体が
        // 視聴画面に置き換わるため、選択状態を明示的にクリアする必要はない。
        .onChange(of: selection) { newValue in
            guard let newValue, let video = videos.first(where: { $0.id == newValue }) else { return }
            if isSelectionMode {
                // リモート動画は削除対象外なので選択トグル自体を無視する(グリッド型と同じ方針)。
                if !video.isRemote {
                    onToggleSelect(video)
                }
                // 同じ行を連続でチェックON/OFFできるよう、都度`nil`に戻す(上記コメント参照)。
                selection = nil
            } else {
                onSelect(video)
            }
        }
        .task(id: videos) {
            await loadFileSizes()
        }
    }
}

/// 「名前」列の1セル(小さいサムネイル+ファイル名)。`Table`の結果ビルダー内に直接
/// `HStack`+`.videoActions`+`.pointingHandOnHover`を書くと型検査が複雑になりすぎて
/// コンパイラが型推論に失敗する(2026-08-14、ヘッダークリックソート追加時に発覚)ため、
/// 別の`View`に切り出している。
private struct NameCell: View {
    let video: VideoItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (VideoItem) -> Void = { _ in }
    var onDeleteLocal: ((VideoItem) async throws -> Void)? = nil

    /// タグ(自動判定+手動追加、2026-08-22追加)。`VideoCardView`と同じ理由で
    /// `EpisodeTagStore`を直接購読する。
    @ObservedObject private var tagStore = EpisodeTagStore.shared

    var body: some View {
        HStack(spacing: 8) {
            // 選択モード中のチェックマーク(2026-08-21追加、グリッド型と同じ方針)。
            // **単なる`Image`ではなく`Button`にする**(2026-08-21修正、「選択モードで
            // ラジオボタンを押しても選択されない」というユーザー報告への対応 ―
            // `VideoCardView`と同じ理由。`Table`の行クリックによるネイティブ選択
            // (`selection`バインディング経由)に依存せず、アイコン自身が確実にタップを
            // 拾って直接`onToggleSelect`を呼ぶ)。
            if isSelectionMode {
                Button {
                    onToggleSelect(video)
                } label: {
                    Image(systemName: video.isRemote ? "circle.dashed" : (isSelected ? "checkmark.circle.fill" : "circle"))
                        .foregroundStyle(video.isRemote ? Color.secondary : (isSelected ? Color.accentColor : Color.secondary))
                }
                .buttonStyle(.plain)
                .disabled(video.isRemote)
                .help(video.isRemote ? "リモート動画はここでは削除できません" : "")
            }
            // 一覧性を優先してごく小さく(2026-08-05、「サムネイルはもう少し
            // 小さくて良い」という要望に対応 ― 旧`VideoHybridRowView`の幅96より
            // 詰めている)。長さバッジは狭いサムネイルに重なって見づらいため出さない
            // (下の「長さ」列に表示)。
            VideoThumbnailView(video: video, width: 56, cornerRadius: 4, showsDurationBadge: false, showsFileSizeInBadge: false)
            Text(video.title)
                .lineLimit(1)
                .truncationMode(.middle)
            // 関連タグ(2026-08-22追加、自動判定+手動追加、`Core/EpisodeTagStore.swift`
            // 参照)。行が1行しか高さを持たないため、タイトルの右にチップを続けて置く
            // (グリッド型は下に置く)。
            let relatedTags = tagStore.allTags(for: video)
            if !relatedTags.isEmpty {
                RelatedTagsRow(tags: relatedTags)
            }
            Spacer(minLength: 4)
            // お気に入りボタン(2026-08-14追加、「リスト時や動画再生時に登録可能に」という
            // 要望への対応)。`.videoActions`(下記)が同じ行に右クリックメニューを付けている
            // ため、`FavoriteButton`自体は`Button`だが右クリックとは競合しない(左クリックの
            // みで反応するため)。
            FavoriteButton(video: video, font: .callout)
        }
        // 右クリックメニュー(Finderで表示/ファイルを削除/ローカルコピーを削除)+確認
        // ダイアログはグリッド型と共通の`VideoActionsModifier`を使い回す。Table内では行の
        // ホバー状態を素直に拾えないため`isHovering`は常にfalse ― command+deleteでの
        // 即時削除だけはこの形式では効かない(右クリック/確認ダイアログ経由の削除は
        // グリッド型と同じく使える)。
        .videoActions(video: video, isHovering: false, onDeleteLocal: onDeleteLocal)
        .pointingHandOnHover()
    }
}

/// 「長さ」列の1セル。サムネイルの読み込み(`VideoThumbnailView`)とは独立に
/// `ThumbnailStore`から長さだけを取得する ― `VideoThumbnailView`側も同じキャッシュを
/// 参照するため、どちらが先に読み込んでも二重にデコードすることはない(`cachedDuration`が
/// ヒットすればそちらを使う)。
private struct DurationCell: View {
    let video: VideoItem

    @State private var duration: TimeInterval?

    var body: some View {
        Text(duration.map(VideoThumbnailView.formatDuration) ?? "—")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .task(id: video.id) {
                if let cached = ThumbnailStore.shared.cachedDuration(for: video) {
                    duration = cached
                    return
                }
                duration = await ThumbnailStore.shared.loadDuration(for: video)
            }
    }
}

/// 「サイズ」列の1セル(2026-08-14追加)。**自前で非同期読み込みはしない**(2026-08-21、
/// 「サイズのソートがおかしい」の修正で撤去 ― 表示中の全動画ぶんの先読みは
/// `VideoTableView.loadFileSizes()`が一括で行い、その結果(`Row.fileSize`)をそのまま
/// 受け取って表示するだけの純粋な表示コンポーネントにした。可視セルだけが個別に非同期取得
/// する以前の作りだと、値が届いても`VideoTableView`の`rows`(＝ソート結果)を再計算させる
/// 手段が無く、ソートが正しく反映されなかったため)。未ダウンロードのリモート動画等
/// サイズを取得する手段が無い動画は`fileSize`が`nil`のまま「—」を表示する。
private struct SizeCell: View {
    let fileSize: Int64?

    private var formatted: String? {
        guard let fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var body: some View {
        Text(formatted ?? "—")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
