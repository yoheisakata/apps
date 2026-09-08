import SwiftUI

/// 選択中のOneDriveリンク1本ぶんの年/月フォルダピッカー+スライドショー設定シート。
/// 旧`Views/HomeView.swift`(起動直後にブロッキング表示していたホーム画面)の
/// フォルダチップUI・スライドショー設定を、`NavigationSplitView`化に伴い単一リンク用の
/// シートへ切り出したもの(`Views/LinkDetailView.swift`のツールバー「年/月を選ぶ」から
/// 開く)。年チップだけだったmyslideshow-ipadと違い、年の下に月チップも展開できる
/// 2階層のフォルダピッカーである点は`HomeView`から変わっていない
/// (`Core/LinkBrowseState.swift`参照)。
struct FolderPickerSheet: View {
    @ObservedObject var state: LinkBrowseState
    @Binding var photoDuration: Double
    @Binding var shuffleEnabled: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var expandedYears: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if state.isLoadingStructure && state.years.isEmpty {
                        ProgressView("フォルダを確認中…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let structureError = state.structureError {
                        Text(structureError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !state.years.isEmpty {
                        HStack(spacing: 12) {
                            Button("全選択") { state.selectAll() }
                            Button("全非選択") { state.selectNone() }
                            Spacer()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        ForEach(state.years, id: \.self) { year in
                            yearRow(year)
                        }
                    }

                    GroupBox("スライドショー設定") {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("ランダム再生", isOn: $shuffleEnabled)
                            HStack {
                                Text("写真の表示時間")
                                Slider(value: $photoDuration, in: 3...15, step: 1)
                                Text("\(Int(photoDuration))秒")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(20)
            }
            .navigationTitle("\(state.link.name)の年/月")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    /// 年フォルダ1つぶんの行: 年チップ(タップでその年の全月を一括選択/解除)+
    /// 展開ボタン(タップで月チップの一覧を開閉)。年チップ自体は展開状態を
    /// トグルしない(選択操作と展開操作を別ジェスチャーに分けている)。
    private func yearRow(_ year: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FolderChip(
                    title: year,
                    isSelected: state.isYearSelected(year),
                    action: { state.toggleYear(year) }
                )
                .frame(maxWidth: .infinity)

                Button {
                    if expandedYears.contains(year) {
                        expandedYears.remove(year)
                    } else {
                        expandedYears.insert(year)
                    }
                } label: {
                    Image(systemName: expandedYears.contains(year) ? "chevron.up.circle" : "chevron.down.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if expandedYears.contains(year) {
                let monthNames = state.monthsFor(year)
                if monthNames.isEmpty {
                    Text("月フォルダがありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(monthNames, id: \.self) { month in
                            FolderChip(
                                title: month,
                                isSelected: state.isMonthSelected(year, month),
                                action: { state.toggleMonth(year, month) }
                            )
                        }
                    }
                    .padding(.leading, 8)
                }
            }
        }
    }
}

/// 年/月フォルダの選択状態を表すカプセル型チップボタン。myslideshow-ipadの
/// `FolderChip`(`Toggle(.checkbox)`が無いiOSでの置き換え)と同じ見た目・役割。
struct FolderChip: View {
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
