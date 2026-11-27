import SwiftUI

struct PhotosView: View {
    @StateObject private var model = PhotosViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("写真整理")
                    .font(.title2).bold()
                Text("Photosから書き出した写真を撮影日時フォルダ（YYYY/MM/MMDD）に整理します。EXIF→コンテンツ作成日→フォルダ名→ファイル名→更新日時の順で日付を推定し、HEICはJPGに変換、同一ファイルはMD5で重複スキップします。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "書き出し元", path: $model.srcPath, exists: model.sourceExists, onPick: model.pickSrc)
                FolderPickerRow(label: "整理先ルート", path: $model.destPath, exists: model.destExists, onPick: model.pickDest, caption: "※ 年フォルダ（例: 2026）は含めないでください。年/月/日フォルダは自動作成されます。")

                Toggle("Dry run（実際には移動しない）", isOn: $model.dryRun)

                Button(model.dryRun ? "確認だけ実行" : "整理を実行") {
                    model.run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobRunner.isRunning || !model.sourceExists || !model.destExists)

                JobLogSectionView(kind: .photos)
            }
            .padding(20)
        }
    }
}
