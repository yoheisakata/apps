import SwiftUI

struct OneDriveSyncView: View {
    @StateObject private var model = OneDriveSyncViewModel.shared
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("OneDrive同期")
                    .font(.title2).bold()
                Text("OneDrive直下のサブフォルダをチェックし、選んだフォルダだけを外付けHDDへミラーリングします(ソースを正とし、ターゲット側にしかないファイルは削除されます)。必ず「差分を確認」を先に実行し、内容を確認してから同期してください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "OneDrive（ソース）", path: $model.sourceRoot, exists: model.sourceExists, onPick: model.pickSource)
                FolderPickerRow(label: "外付けHDD（ターゲット・削除が起きる）", path: $model.targetRoot, exists: model.targetExists, onPick: model.pickTarget)

                if model.subfolders.isEmpty {
                    Text(model.sourceExists ? "サブフォルダが見つかりません" : "フォルダが見つかりません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("対象サブフォルダ").font(.headline)
                            Spacer()
                            Button("全選択") { model.selectAll() }
                                .disabled(jobRunner.isRunning)
                            Button("全解除") { model.selectNone() }
                                .disabled(jobRunner.isRunning)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 4) {
                            ForEach(model.subfolders, id: \.self) { name in
                                Toggle(name, isOn: Binding(
                                    get: { model.selectedSubfolders.contains(name) },
                                    set: { on in
                                        if on { model.selectedSubfolders.insert(name) } else { model.selectedSubfolders.remove(name) }
                                    }
                                ))
                                .disabled(jobRunner.isRunning)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                Toggle("更新日時は考慮しない（サイズのみで比較）", isOn: $model.sizeOnly)
                    .disabled(jobRunner.isRunning)
                    .help("OneDriveは中身が同じファイルでも同期のたびに更新日時だけズレることがあります。ONにするとサイズだけで比較し、更新日時だけの違いは差分として検出しません。")

                Button("差分を確認") {
                    model.checkDiff()
                }
                .buttonStyle(.bordered)
                .disabled(jobRunner.isRunning || !model.sourceExists || !model.targetExists || model.selectedSubfolders.isEmpty)

                if !model.fileChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("変更ファイル (\(model.fileChanges.count)件)").font(.headline)
                        FileChangesList(changes: model.fileChanges)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !model.results.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("全体の状況").font(.headline)
                        ResultsTable(results: model.results)

                        HStack(spacing: 16) {
                            Label("追加 \(model.totalAdd)", systemImage: "plus.circle").foregroundStyle(.green)
                            Label("更新 \(model.totalMod)", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
                            Label("削除 \(model.totalDel)", systemImage: "minus.circle").foregroundStyle(.red)
                        }
                        .font(.callout)

                        HStack {
                            Button(model.hasChanges ? "同期を実行…" : "同期を実行（差分なし）") {
                                model.requestSync()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(jobRunner.isRunning || !model.hasChanges)

                            Button("レポートを保存…") {
                                model.saveReport()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                JobLogSectionView(kind: .oneDriveSync)
            }
            .padding(20)
        }
        .alert("同期を実行しますか？", isPresented: $model.showConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("実行", role: .destructive) {
                model.confirmSync()
            }
        } message: {
            Text("ソース: \(model.sourceRoot)\nターゲット: \(model.targetRoot)\n対象: \(model.results.map { $0.name }.joined(separator: ", "))\n\n追加=\(model.totalAdd) 更新=\(model.totalMod) 削除=\(model.totalDel)\n\nターゲット側にしかないファイルが削除されます。")
        }
    }
}

/// 差分確認後に出す「全体の状況」テーブル。フォルダごとにサイズ・ファイル数(ソース/ターゲット)・
/// 同期状態を1行にまとめ、rsyncの差分件数を待たず目視でも量が合っているか確認できるようにする。
private struct ResultsTable: View {
    let results: [OneDriveSyncViewModel.FolderDiffResult]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text("")
                Text("ファイル数").gridCellColumns(2)
                Text("サイズ").gridCellColumns(2)
                Text("")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            GridRow {
                Text("フォルダ")
                Text("OneDrive")
                Text("ターゲット")
                Text("OneDrive")
                Text("ターゲット")
                Text("状態")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            Divider().gridCellColumns(6)

            ForEach(results) { result in
                let sizeMatch = result.sourceSizeBytes == result.targetSizeBytes
                let countMatch = result.sourceFileCount == result.targetFileCount
                GridRow {
                    Text(result.name)
                    Text("\(result.sourceFileCount)件")
                        .foregroundStyle(countMatch ? Color.green : Color.orange)
                    Text("\(result.targetFileCount)件")
                        .foregroundStyle(countMatch ? Color.green : Color.orange)
                    Text(ByteFmt.string(result.sourceSizeBytes))
                        .foregroundStyle(sizeMatch ? Color.green : Color.orange)
                    Text(ByteFmt.string(result.targetSizeBytes))
                        .foregroundStyle(sizeMatch ? Color.green : Color.orange)
                    statusCell(result)
                }
                .font(.caption)
            }
        }
    }

    private func statusCell(_ result: OneDriveSyncViewModel.FolderDiffResult) -> some View {
        Group {
            if result.diff.hasChanges {
                HStack(spacing: 10) {
                    countBadge(result.diff.addCount, "plus.circle", .green)
                    countBadge(result.diff.modCount, "arrow.triangle.2.circlepath", .blue)
                    countBadge(result.diff.delCount, "minus.circle", .red)
                }
            } else {
                Label("同期済み (\(result.checkedAt.formatted("HH:mm")))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func countBadge(_ count: Int, _ icon: String, _ color: Color) -> some View {
        Label("\(count)", systemImage: icon)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

/// 差分確認で見つかった追加/更新/削除ファイルの一覧。フォルダごとにSectionでまとめ、
/// 色分けしたアイコンで種別を示す(緑=追加/青=更新/赤=削除)。`List`はSwiftUIの標準機能で
/// 行を遅延描画するため、数百〜数千件規模の差分でも軽い(`Grid`は非遅延なので不向き)。
private struct FileChangesList: View {
    let changes: [OneDriveSyncViewModel.FileChange]

    private var grouped: [(folder: String, items: [OneDriveSyncViewModel.FileChange])] {
        let groups = Dictionary(grouping: changes, by: \.folder)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.folder) { group in
                Section(header: Text("\(group.folder) (\(group.items.count)件)")) {
                    ForEach(group.items) { change in
                        row(change)
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(height: 280)
    }

    private func row(_ change: OneDriveSyncViewModel.FileChange) -> some View {
        HStack(alignment: .top, spacing: 8) {
            icon(for: change.kind)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(change.path)
                    .font(.caption)
                    .textSelection(.enabled)
                if let reason = change.reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func icon(for kind: OneDriveSyncViewModel.FileChange.Kind) -> some View {
        switch kind {
        case .added:
            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
        case .modified:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.blue)
        case .deleted:
            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
        }
    }
}
