import SwiftUI

/// 選択中のOneDriveリンク1本ぶんのグリッド画面。中身(サムネイルグリッド・
/// ビューア・スライドショー)は`Views/GridView.swift`に委譲し、このビューは
/// フォルダ選択に応じたフェーズ2スキャンのトリガー(初回自動・
/// `.refreshable`・フォルダピッカーを閉じたとき)とナビゲーションタイトル・
/// フォルダピッカーの呼び出しだけを担う ― mytube-ipadの`Views/SourceGridView.swift`
/// (共有リンクのスキャンだけを担う薄いラッパー)と同じ役割分担。
/// `ContentView`が`.id(link.id)`を付けて呼ぶため、別のリンクに切り替えると
/// `showingPicker`等の`@State`は自動的にリセットされる。
struct LinkDetailView: View {
    let link: HardcodedLink
    @ObservedObject var browseState: LinkBrowseState
    let gallery: LinkGalleryState
    @Binding var photoDuration: Double
    @Binding var shuffleEnabled: Bool
    @Binding var sortOrder: SortOrder
    @Binding var showSizeBadge: Bool
    @Binding var showDateBadge: Bool
    let onScan: () async -> Void

    @State private var showingPicker = false

    var body: some View {
        GridView(
            items: gallery.items,
            isLoading: gallery.isLoading,
            errorMessage: gallery.errorMessage,
            shuffleEnabled: shuffleEnabled,
            sortOrder: sortOrder,
            showSizeBadge: showSizeBadge,
            showDateBadge: showDateBadge
        )
        .navigationTitle(link.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 一覧が既に表示されている状態でのバックグラウンド更新中
            // (プルダウン更新・フォルダピッカーを閉じた直後の再スキャン)は
            // `GridView`側の「一覧が空のときだけの全画面ローディング」分岐を
            // 通らないため、代わりにここへ控えめなインジケーターを出す
            // (mytube-ipadの`SourceGridView`と同じ考え方)。
            if gallery.isLoading && !gallery.items.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            // 並び替え・バッジ表示トグル(2026-09-07追加、mygallery Mac版の
            // ツールバー相当)。並び替えは種類が多いので`Menu`に、バッジ2種は
            // Mac版と同じくオン/オフの押し込みボタンにした。
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("並び替え", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage).tag(order)
                        }
                    }
                } label: {
                    Label("並び替え", systemImage: "arrow.up.arrow.down.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showDateBadge) {
                    Label("月日を表示", systemImage: "calendar")
                }
                .toggleStyle(.button)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showSizeBadge) {
                    Label("サイズを表示", systemImage: "scalemass")
                }
                .toggleStyle(.button)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPicker = true
                } label: {
                    Label("年/月を選ぶ", systemImage: "calendar.badge.clock")
                }
            }
        }
        .refreshable {
            await onScan()
        }
        .task(id: link.id) {
            // フォルダ構造(フェーズ1)の取得だけをここで起動する。実データ
            // (フェーズ2)の自動スキャンは、フォルダ構造が揃って既定選択が
            // 決まった後(`browseState.structureLoaded`)に行う ―
            // 下の`.onChange`参照。
            browseState.loadStructureIfNeeded()
        }
        .onChange(of: browseState.structureLoaded) { _, loaded in
            guard loaded, !gallery.hasScannedOnce else { return }
            Task { await onScan() }
        }
        .sheet(isPresented: $showingPicker, onDismiss: {
            // ピッカーを閉じたら選択が変わっているかもしれないので、都度スキャンし
            // 直す。チップを1つ切り替えるたびに毎回OneDriveへ取りに行くと
            // (`CLAUDE.md`に記載の通りこのアプリのフェーズ2スキャンは重いため)
            // 負荷が大きいため、シートを閉じたタイミングにまとめている
            // (mytube-ipadのようにフォルダ選択変更のたびに即スキャンする設計とは
            // 意図的に変えてある)。
            Task { await onScan() }
        }) {
            FolderPickerSheet(state: browseState, photoDuration: $photoDuration, shuffleEnabled: $shuffleEnabled)
        }
    }
}

/// 1本のOneDriveリンクぶんのフェーズ2スキャン結果(`ContentView`が
/// `link.id`をキーに保持する)。
struct LinkGalleryState {
    var items: [MediaItem] = []
    var isLoading = false
    var errorMessage: String?
    /// このリンクを開いてから一度でも(自動・手動問わず)スキャンしたか ―
    /// フォルダ構造読み込み完了時の自動スキャンを最初の1回だけに留めるためのフラグ。
    var hasScannedOnce = false
    /// このリンクへの`scan()`呼び出しの単調カウンタ。プルダウン更新・フォルダピッカーの
    /// クローズ・初回自動実行が短時間に重なって複数の`scan()`呼び出しが並行するケースで、
    /// 先に開始したが後から完了した呼び出しが、後に開始したが先に完了した呼び出しの
    /// 結果を上書きしてしまわないようにするためのガード(`ContentView.scan(link:)`参照)。
    var generation = 0
}
