import SwiftUI

struct CacheCleanerView: View {
    @StateObject private var vm = CacheViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .alert("ゴミ箱に移動しますか？", isPresented: $showConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("ゴミ箱に移動", role: .destructive) {
                Task { await vm.clean() }
            }
        } message: {
            Text("選択した約 \(ByteFmt.string(vm.selectedSize)) 分のファイルをゴミ箱へ移動します。ゴミ箱を空にするまで復元できます。")
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("クリーン")
                    .font(.headline)
                if vm.hasScanned {
                    Text("合計 \(ByteFmt.string(vm.totalSize)) / 選択中 \(ByteFmt.string(vm.selectedSize))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("スキャンして削除できるファイルを探します")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await vm.scan() }
            } label: {
                Label("スキャン", systemImage: "magnifyingglass")
            }
            .disabled(vm.isScanning || vm.isCleaning)

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
            .disabled(!vm.hasSelection || vm.isScanning || vm.isCleaning)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isScanning {
            Spacer()
            ProgressView("スキャン中…")
            Spacer()
        } else if vm.isCleaning {
            Spacer()
            ProgressView("ゴミ箱へ移動中…")
            Spacer()
        } else if !vm.hasScanned {
            emptyState(text: "「スキャン」を押して開始してください。")
        } else if vm.categories.isEmpty {
            emptyState(text: vm.status.isEmpty ? "削除できるファイルはありません。" : vm.status)
        } else {
            List {
                ForEach($vm.categories) { $category in
                    categorySection($category)
                }
            }
            .listStyle(.inset)
            if !vm.status.isEmpty {
                Text(vm.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private func categorySection(_ category: Binding<CacheCategory>) -> some View {
        Section {
            DisclosureGroup(isExpanded: category.isExpanded) {
                ForEach(category.items) { $item in
                    HStack {
                        Toggle(isOn: $item.isSelected) {
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(ByteFmt.string(item.size))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } label: {
                HStack {
                    Toggle(isOn: Binding(
                        get: { category.wrappedValue.allSelected },
                        set: { vm.setAllSelected(in: category.wrappedValue.id, to: $0) }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.wrappedValue.title)
                                    .font(.body.weight(.medium))
                                Text(category.wrappedValue.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: category.wrappedValue.systemImage)
                        }
                    }
                    Spacer()
                    Text(ByteFmt.string(category.wrappedValue.totalSize))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
