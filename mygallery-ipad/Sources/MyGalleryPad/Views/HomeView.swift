import SwiftUI

/// 起動直後のホーム画面。myslideshow-ipadの`Views/HomeView.swift`(年別チップの
/// レイアウト・「全選択」/「全非選択」ボタン・スライドショー設定)がベースだが、
/// **年チップだけだったmyslideshow-ipadと違い、年の下に月チップも展開できる
/// 2階層のフォルダピッカーにしてある(このアプリ独自の新規部分)** ―
/// mygallery(Mac版)の`OneDriveFolderTreeViewController`(`NSOutlineView`の
/// 年/月フォルダツリー)が持っていた粒度をSwiftUIのチップUIに置き換えたもの。
///
/// もう1つの大きな違い: myslideshow-ipadはここから直接スライドショーへ遷移するが、
/// MyGallery Padはブラウズ可能な**グリッド画面**(`Views/GridView.swift`)へ遷移する
/// (スライドショーはグリッド画面のツールバーから始める) ― 「開く」ボタンの文言も
/// それに合わせて「グリッドを開く」にしてある。
struct HomeView: View {
    let states: [LinkBrowseState]
    let isLoadingItems: Bool
    let errorMessage: String?
    @Binding var photoDuration: Double
    @Binding var shuffleEnabled: Bool
    let onOpen: () -> Void

    @State private var expandedYears: Set<String> = []

    private var canOpen: Bool {
        !isLoadingItems && states.contains { !$0.selectedLeafFolders().isEmpty || $0.months.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                ForEach(states, id: \.link.id) { state in
                    linkSection(state)
                }

                if isLoadingItems {
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

                Button("グリッドを開く", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!canOpen)
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            for state in states { state.loadStructureIfNeeded() }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("MyGallery Pad")
                .font(.title.weight(.bold))
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func linkSection(_ state: LinkBrowseState) -> some View {
        GroupBox(state.link.name) {
            VStack(alignment: .leading, spacing: 10) {
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
                        yearRow(state, year)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isLoadingItems)
    }

    /// 年フォルダ1つぶんの行: 年チップ(タップでその年の全月を一括選択/解除)+
    /// 展開ボタン(タップで月チップの一覧を開閉)。年チップ自体は展開状態を
    /// トグルしない(選択操作と展開操作を別ジェスチャーに分けている)。
    private func yearRow(_ state: LinkBrowseState, _ year: String) -> some View {
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
