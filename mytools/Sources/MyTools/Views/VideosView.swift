import SwiftUI

struct VideosView: View {
    @StateObject private var model = VideosViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("動画整理")
                    .font(.title2).bold()
                Text("Photosから書き出した動画を撮影日時フォルダ（YYYY/MM/MMDD）に整理します。QuickTimeメタデータ→コンテンツ作成日→フォルダ名→ファイル名→更新日時の順で日付を推定し、同一ファイルはMD5で重複スキップします。移動が完了したファイルから順にその場でH.265エンコードします（H.264などH.265以外は常に再エンコードして統一。すでにH.265で.mov等の場合はコンテナ変換のみ・劣化なし）。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "書き出し元", path: $model.srcPath, exists: model.sourceExists, onPick: model.pickSrc)
                FolderPickerRow(label: "整理先ルート", path: $model.destPath, exists: model.destExists, onPick: model.pickDest, caption: "※ 年フォルダ（例: 2026）は含めないでください。年/月/日フォルダは自動作成されます。")

                Toggle("Dry run（実際には移動・変換しない）", isOn: $model.dryRun)

                Divider()

                Toggle("エンコードしない（整理・移動のみ行う）", isOn: $model.skipEncode)

                if !model.skipEncode {
                    HStack {
                        Text("品質 (CRF): \(Int(model.crf))")
                        Slider(value: $model.crf, in: 18...28, step: 1)
                    }
                    Picker("速度プリセット", selection: $model.preset) {
                        ForEach(EncodeViewModel.presets, id: \.self) { Text($0) }
                    }
                    .frame(maxWidth: 240)
                }

                Button(model.dryRun ? "確認だけ実行" : "実行") {
                    model.run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobRunner.isRunning || !model.canRun)

                JobLogSectionView(kind: .videos)
            }
            .padding(20)
        }
    }
}
