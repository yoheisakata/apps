import SwiftUI

struct VerifyView: View {
    @StateObject private var model = VerifyViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("写真検証")
                    .font(.title2).bold()
                Text("<root>/<MM>/<MMDD>/YYYY_MMDD_HHMMSS.<ext> という想定構造から外れたファイル（名前違い・フォルダ違い・MM直下にある等）を検出します。rootは年フォルダ（例: .../0_Photo/2026）を指定してください。数字以外で始まるフォルダはスキップします。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "対象ルート（年フォルダ）", path: $model.rootPath, exists: model.rootExists, onPick: model.pickRoot)

                Picker("モード", selection: $model.mode) {
                    Text("確認のみ").tag(VerifyMode.report)
                    Text("Dry run（修正内容を表示）").tag(VerifyMode.dryRun)
                    Text("修正実行").tag(VerifyMode.fix)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if model.mode == .fix {
                    Label("実際にファイルを移動・リネームします", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button(model.mode == .fix ? "修正を実行" : "検証を実行") {
                    model.run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobRunner.isRunning || !model.rootExists)

                JobLogSectionView(kind: .verify)
            }
            .padding(20)
        }
    }
}
