import SwiftUI

struct SyncView: View {
    @StateObject private var model = SyncViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("同期")
                    .font(.title2).bold()
                Text("2つのHDD間でソースを正としてターゲットをミラーリングします。ターゲット側にしかないファイルは削除されます。必ず「差分を確認」を先に実行し、内容を確認してから同期してください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "ソース（正とする側）", path: $model.sourcePath, exists: model.sourceExists, onPick: model.pickSource)
                FolderPickerRow(label: "ターゲット（合わせる側・削除が起きる）", path: $model.targetPath, exists: model.targetExists, onPick: model.pickTarget)

                Button("差分を確認") {
                    model.checkDiff()
                }
                .buttonStyle(.bordered)
                .disabled(jobRunner.isRunning || !model.sourceExists || !model.targetExists)

                if let diff = model.lastDiff {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            Label("追加 \(diff.addCount)", systemImage: "plus.circle").foregroundStyle(.green)
                            Label("更新 \(diff.modCount)", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
                            Label("削除 \(diff.delCount)", systemImage: "minus.circle").foregroundStyle(.red)
                        }
                        .font(.callout)

                        HStack {
                            Button(diff.hasChanges ? "同期を実行…" : "同期を実行（差分なし）") {
                                model.requestSync()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(jobRunner.isRunning || !diff.hasChanges)

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

                JobLogSectionView(kind: .sync)
            }
            .padding(20)
        }
        .alert("同期を実行しますか？", isPresented: $model.showConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("実行", role: .destructive) {
                model.confirmSync()
            }
        } message: {
            if let diff = model.lastDiff {
                Text("ソース: \(model.sourcePath)\nターゲット: \(model.targetPath)\n\n追加=\(diff.addCount) 更新=\(diff.modCount) 削除=\(diff.delCount)\n\nターゲット側にしかない\(diff.delCount)件のファイルが削除されます。")
            }
        }
    }
}
