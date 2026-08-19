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

    /// 単一選択のみ。Finder本来の「選択してから別操作」というワークフローは持たず、選択即
    /// 再生のトリガーとして使うだけなので複数選択のUIは不要。
    @State private var selection: VideoItem.ID?
    /// ヘッダークリックでのソート(2026-08-14追加、「動画リスト表示でヘッダーをクリックしたら
    /// ソートしてほしい。ソート機能は一覧のみでヘッダークリックでできるようにして」という
    /// 要望への対応 ― 以前あった`TopBarView`の「並び替え」メニュー(`SortOption`)はこの機能に
    /// 一本化する形で撤去済み、グリッド表示はファイル名昇順の固定順になった)。`Table`標準の
    /// `sortOrder`機構(クリックで矢印が出て並び替わる、ネイティブのFinder風挙動)をそのまま使う。
    @State private var sortOrder: [KeyPathComparator<Row>] = [KeyPathComparator(\.title)]

    /// `Table`の`sortUsing:`は`KeyPathComparator`(値がその場で`Comparable`である必要がある)
    /// を要求するため、`VideoItem`をそのまま渡さずこの薄いラッパーに変換してから`Table`に渡す
    /// ― `video.remoteKind`(enum)は`Comparable`ではないため`sourceLabel`という文字列に、
    /// `duration`(長さ、`VideoItem`自体は保持せず`ThumbnailStore`のキャッシュから同期的に
    /// 引く)は`Optional<TimeInterval>`をこのファイル内で`Comparable`にした上で保持する。
    private struct Row: Identifiable {
        let video: VideoItem
        var id: VideoItem.ID { video.id }
        var title: String { video.title }
        var channel: String { video.channel }
        var sourceLabel: String { video.remoteKind?.displayName ?? "ローカル" }
        /// `DurationCell`が非同期取得した値をこの配列には反映できない(`Row`はソートのたびに
        /// `videos`から作り直す値型のため)ので、`ThumbnailStore`が既にキャッシュ済みの値
        /// (同期的に読める)を使う。まだキャッシュに無い動画は`nil`扱い。
        /// `ThumbnailStore`は`@MainActor`だが、`Row`は`Table`の`RowValue`要件上`Identifiable`を
        /// nonisolatedで満たす必要があるため型自体には`@MainActor`を付けられない ―
        /// `MainActor.assumeIsolated`で「実際には`body`(MainActor)からしか呼ばれない」ことを
        /// コンパイラに伝えて同期的にブリッジする。
        var duration: TimeInterval? {
            video.knownDurationSeconds ?? MainActor.assumeIsolated { ThumbnailStore.shared.cachedDuration(for: video) }
        }

        /// `KeyPathComparator`にそのまま渡せる非Optional版(2026-08-14追加)。`TimeInterval?`に
        /// `Comparable`適合(下記`extension Optional`)を追加して直接渡すと、`Table`の
        /// 結果ビルダーの型検査がクラッシュする不具合(実機で確認、"failed to produce
        /// diagnostic"というコンパイラ内部エラー)があったため、代わりにこの非Optionalな
        /// キーを使う ― 長さ不明の動画は`.greatestFiniteMagnitude`(最大値)を返し、
        /// 昇順ソート時に自然と末尾へ回る(降順時は先頭に来る点だけ`nil`の厳密な「常に末尾」
        /// 規約とは異なるが、実用上の影響は小さいため許容している)。
        var durationSortKey: TimeInterval { duration ?? .greatestFiniteMagnitude }

        /// 「サイズ」列(2026-08-14追加、「ハイブリッド表示のときは動画のサイズをカラムで
        /// 表示して」という要望への対応)。`duration`/`durationSortKey`と同じ理由で
        /// `FileSizeStore`の同期キャッシュ読み取りを使い、`Int64.max`を未取得時のフォール
        /// バックにする(昇順ソートで自然と末尾に回る)。
        var fileSize: Int64? {
            MainActor.assumeIsolated { FileSizeStore.shared.cachedSize(for: video) }
        }
        var fileSizeSortKey: Int64 { fileSize ?? .max }
    }

    private var rows: [Row] {
        videos.map(Row.init).sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("名前", sortUsing: KeyPathComparator(\.title)) { row in
                NameCell(video: row.video)
            }
            .width(min: 280, ideal: 520)

            TableColumn("長さ", sortUsing: KeyPathComparator(\.durationSortKey)) { row in
                DurationCell(video: row.video)
            }
            .width(min: 56, ideal: 64)

            TableColumn("サイズ", sortUsing: KeyPathComparator(\.fileSizeSortKey)) { row in
                SizeCell(video: row.video)
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
            onSelect(video)
        }
    }
}

/// 「名前」列の1セル(小さいサムネイル+ファイル名)。`Table`の結果ビルダー内に直接
/// `HStack`+`.videoActions`+`.pointingHandOnHover`を書くと型検査が複雑になりすぎて
/// コンパイラが型推論に失敗する(2026-08-14、ヘッダークリックソート追加時に発覚)ため、
/// 別の`View`に切り出している。
private struct NameCell: View {
    let video: VideoItem

    var body: some View {
        HStack(spacing: 8) {
            // 一覧性を優先してごく小さく(2026-08-05、「サムネイルはもう少し
            // 小さくて良い」という要望に対応 ― 旧`VideoHybridRowView`の幅96より
            // 詰めている)。長さバッジは狭いサムネイルに重なって見づらいため出さない
            // (下の「長さ」列に表示)。
            VideoThumbnailView(video: video, width: 56, cornerRadius: 4, showsDurationBadge: false, showsFileSizeInBadge: false)
            Text(video.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            // お気に入りボタン(2026-08-14追加、「リスト時や動画再生時に登録可能に」という
            // 要望への対応)。`.videoActions`(下記)が同じ行に右クリックメニューを付けている
            // ため、`FavoriteButton`自体は`Button`だが右クリックとは競合しない(左クリックの
            // みで反応するため)。
            FavoriteButton(video: video, font: .callout)
        }
        // 右クリックメニュー(Finderで表示/ローカルコピーを削除)+確認ダイアログは
        // グリッド型と共通の`VideoActionsModifier`を使い回す。Table内では行のホバー
        // 状態を素直に拾えないため`isHovering`は常にfalse ― command+deleteでの
        // 即時削除だけはこの形式では効かない(右クリック/確認ダイアログ経由の削除は
        // グリッド型と同じく使える)。
        .videoActions(video: video, isHovering: false)
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

/// 「サイズ」列の1セル(2026-08-14追加)。`DurationCell`と同じ非同期読み込み+キャッシュの
/// パターンを`FileSizeStore`に対して行う。未ダウンロードのリモート動画はサイズを取得する
/// 手段が無いため「—」のまま。
private struct SizeCell: View {
    let video: VideoItem

    @State private var fileSize: Int64?

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
            .task(id: video.id) {
                if let cached = FileSizeStore.shared.cachedSize(for: video) {
                    fileSize = cached
                    return
                }
                fileSize = await FileSizeStore.shared.loadSize(for: video)
            }
    }
}
