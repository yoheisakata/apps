import SwiftUI

struct StorageAnalysisView: View {
    @StateObject private var vm = StorageAnalysisViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .alert("ゴミ箱に移動しますか？", isPresented: $showConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("ゴミ箱に移動", role: .destructive) {
                Task { await vm.deleteSelected() }
            }
        } message: {
            Text("選択した \(vm.selectedFiles.count) 件・約 \(ByteFmt.string(vm.selectedSize)) 分のファイルをゴミ箱へ移動します。ゴミ箱を空にするまで復元できます。")
        }
        .alert("削除できなかった項目があります", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ストレージ分析")
                .font(.headline)
            FolderPickerRow(
                label: "対象フォルダ",
                path: $vm.rootPath,
                exists: vm.rootExists,
                onPick: vm.pickRoot
            )
            Label("OneDrive/iCloud等の同期フォルダ内のファイルをゴミ箱に移動すると、クラウド側からも削除されます", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            HStack(alignment: .center) {
                if vm.hasScanned {
                    Text("走査サイズ合計 \(ByteFmt.string(vm.totalSize))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("フォルダ配下を再帰スキャンし、内訳と大きいファイルを一覧表示します")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await vm.scan() }
                } label: {
                    Label("スキャン", systemImage: "magnifyingglass")
                }
                .disabled(vm.isScanning || vm.isDeleting || !vm.rootExists)

                Button(role: .destructive) {
                    if jobRunner.isRunning {
                        vm.errorMessage = "他の処理(\(jobRunner.title))を実行中です。完了してからもう一度お試しください。"
                    } else {
                        showConfirm = true
                    }
                } label: {
                    Label("ゴミ箱へ移動", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.hasSelection || vm.isScanning || vm.isDeleting)
            }
        }
        .padding()
        .padding(.bottom, 0)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isScanning {
            Spacer()
            ProgressView("スキャン中…(フォルダが大きいと数分かかることがあります)")
            Spacer()
        } else if vm.isDeleting {
            Spacer()
            ProgressView("ゴミ箱へ移動中…")
            Spacer()
        } else if !vm.hasScanned {
            emptyState(text: "「スキャン」を押して開始してください。")
        } else if vm.breakdown.isEmpty && vm.largeFiles.isEmpty {
            emptyState(text: vm.status.isEmpty ? "対象がありません。" : vm.status)
        } else {
            List {
                Section("内訳(直下フォルダ別、上位15件)") {
                    ForEach(vm.breakdown.prefix(15)) { item in
                        breakdownRow(item)
                    }
                }
                Section {
                    ForEach($vm.largeFiles) { $file in
                        largeFileRow($file)
                    }
                } header: {
                    HStack {
                        Text("大きいファイル(\(ByteFmt.string(StorageAnalyzer.largeFileThresholdBytes)) 以上・\(vm.largeFiles.count) 件)")
                        Spacer()
                        if !vm.largeFiles.isEmpty {
                            Toggle("すべて選択", isOn: Binding(
                                get: { vm.largeFiles.allSatisfy { $0.isSelected } },
                                set: { vm.setAllSelected($0) }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .listStyle(.inset)
            if vm.hasSelection {
                Text("選択中 \(vm.selectedFiles.count) 件・約 \(ByteFmt.string(vm.selectedSize))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], 10)
            }
        }
    }

    private func breakdownRow(_ item: StorageBreakdownItem) -> some View {
        HStack(spacing: 8) {
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 170, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: geo.size.width * breakdownRatio(item.size), height: 14)
            }
            .frame(height: 14)
            Text(ByteFmt.string(item.size))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .contextMenu {
            Button("Finderで表示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    private func breakdownRatio(_ size: Int64) -> CGFloat {
        guard let maxSize = vm.breakdown.first?.size, maxSize > 0 else { return 0 }
        return CGFloat(size) / CGFloat(maxSize)
    }

    private func largeFileRow(_ file: Binding<LargeFileItem>) -> some View {
        HStack {
            Toggle(isOn: file.isSelected) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.wrappedValue.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.wrappedValue.url.deletingLastPathComponent().path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            Text(ByteFmt.string(file.wrappedValue.size))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contextMenu {
            Button("Finderで表示") {
                NSWorkspace.shared.activateFileViewerSelecting([file.wrappedValue.url])
            }
        }
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
