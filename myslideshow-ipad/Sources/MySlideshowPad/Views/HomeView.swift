import SwiftUI

/// 起動直後のホーム画面。myslideshow(Mac版)の`Views/HomeView.swift`から移植 ―
/// 表示モード(ウィンドウ内/全画面/PIP)のセグメントピッカーは無い(`ContentView`の項参照、
/// iPadは常にフルスクリーンのため対応する設定自体が無い)。年別フォルダのチェックリストは
/// `HardcodedLink.availableFolders`のままハードコードで、OneDriveのスキャンは行わない ―
/// 実際にOneDriveへ写真・動画を取得しに行くのは「スライドショー開始」を押した瞬間だけ。
///
/// **チェックボックスは`Toggle(.checkbox)`の代わりに自前のカプセル型チップボタン**
/// (`FolderChip`)を使う ― iOSに`.checkbox`トグルスタイルが無いための置き換え。選択中は
/// 塗りつぶし+チェックマーク、未選択は輪郭のみ、という見た目でMac版のチェックボックスに
/// 近い一目での状態把握を保つ。全体を`ScrollView`で包んでいる ― Mac版はウィンドウ固定
/// 420×560だが、iPadは画面サイズ・向き(縦/横)が機種によって変わるため、内容が画面に
/// 収まらない場合でもスクロールで必ず操作できるようにするため。
struct HomeView: View {
    let links: [HardcodedLink]
    /// キーは`HardcodedLink.id`。
    let selectedFolders: [String: Set<String>]
    /// 「スライドショー開始」を押してOneDriveへ実際に取得しに行っている間`true`。
    let isLoading: Bool
    let errorMessage: String?
    @Binding var photoDuration: Double
    @Binding var shuffleEnabled: Bool
    /// スライドショー全体の時間制限(分)。`nil`は無制限。
    @Binding var timeLimitMinutes: Int?
    let onToggleFolder: (HardcodedLink, String) -> Void
    let onSetAllFolders: (HardcodedLink, Bool) -> Void
    let onStart: () -> Void

    /// 時間制限スライダーの刻み: 5分刻みで5〜60分、最後の1つは「無制限」(`nil`)。
    private static let timeLimitOptions: [Int?] = stride(from: 5, through: 60, by: 5).map { $0 } + [nil]

    private var timeLimitIndex: Binding<Double> {
        Binding(
            get: { Double(Self.timeLimitOptions.firstIndex(of: timeLimitMinutes) ?? Self.timeLimitOptions.count - 1) },
            set: { newValue in
                let index = Int(newValue.rounded())
                timeLimitMinutes = Self.timeLimitOptions[min(max(index, 0), Self.timeLimitOptions.count - 1)]
            }
        )
    }

    private var timeLimitLabel: String {
        timeLimitMinutes.map { "\($0)分" } ?? "無制限"
    }

    private var canStart: Bool {
        !isLoading && links.contains { !(selectedFolders[$0.id] ?? Set($0.availableFolders)).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                ForEach(links) { link in
                    linkSection(link)
                }

                if isLoading {
                    ProgressView("読み込み中…")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                GroupBox("スライドショー設定") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("写真の表示時間")
                            Slider(value: $photoDuration, in: 3...15, step: 1)
                            Text("\(Int(photoDuration))秒")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        Toggle("順番をシャッフル", isOn: $shuffleEnabled)
                        HStack {
                            Text("時間制限")
                            Slider(value: timeLimitIndex, in: 0...Double(Self.timeLimitOptions.count - 1), step: 1)
                            Text(timeLimitLabel)
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .padding(.top, 6)
                }

                Button("スライドショー開始", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!canStart)
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("MySlideshow")
                .font(.title.weight(.bold))
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func linkSection(_ link: HardcodedLink) -> some View {
        GroupBox(link.name) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button("全選択") { onSetAllFolders(link, true) }
                    Button("全非選択") { onSetAllFolders(link, false) }
                    Spacer()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(link.availableFolders, id: \.self) { folder in
                        FolderChip(
                            title: folder,
                            isSelected: (selectedFolders[link.id] ?? Set(link.availableFolders)).contains(folder),
                            action: { onToggleFolder(link, folder) }
                        )
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isLoading)
    }
}

/// 年別フォルダの選択状態を表すカプセル型チップボタン。`Toggle(.checkbox)`(iOSに無い)の
/// 代替として導入した ― 選択中は塗りつぶし+チェックマーク、未選択は輪郭のみ。
private struct FolderChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
