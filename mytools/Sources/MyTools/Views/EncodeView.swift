import SwiftUI

struct EncodeView: View {
    @StateObject private var model = EncodeViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("エンコード")
                    .font(.title2).bold()
                Text("任意フォルダ配下の動画をH.265(HEVC)+mp4に統一します。H.265以外は再エンコード、H.265だが.mov等はコンテナ変換のみ（劣化なし・高速）、H.265+mp4は変更しません。成功後は元ファイルを削除します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "対象フォルダ", path: $model.folderPath, exists: model.folderExists, onPick: model.pickFolder)

                Toggle("コンテナ変換のみ（再エンコードしない）", isOn: $model.remuxOnly)

                if !model.remuxOnly {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("品質 (CRF): \(Int(model.crf))")
                            Slider(value: $model.crf, in: 18...28, step: 1)
                        }
                        Text("18=高画質・大きい 〜 28=標準・小さい")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("速度プリセット", selection: $model.preset) {
                            ForEach(EncodeViewModel.presets, id: \.self) { Text($0) }
                        }
                        .frame(maxWidth: 240)
                    }
                }

                HStack {
                    Text("最小サイズフィルター (MB)")
                    TextField("0 = 制限なし", value: $model.minSizeMB, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Dry run（実際には変換しない）", isOn: $model.dryRun)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("スキャン（残り件数を確認）") {
                            model.scan()
                        }
                        .disabled(model.isScanning || jobRunner.isRunning || !model.folderExists)

                        if model.isScanning {
                            ProgressView().controlSize(.small)
                            Text(model.scanProgressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("中止") { model.cancelScan() }
                        }
                    }

                    if let result = model.scanResult {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("動画ファイル: \(result.total)件")
                            Text("エンコードが必要: \(result.toEncode)件（合計 \(ByteFmt.string(Int64(result.toEncodeSizeMB * 1024 * 1024)))）")
                                .bold()
                            Text("コンテナ変換のみ: \(result.toRemux)件 / 変換済み: \(result.alreadyDone)件"
                                + (result.errorCount > 0 ? " / エラー: \(result.errorCount)件" : ""))
                            if !result.errorSamples.isEmpty {
                                ForEach(result.errorSamples, id: \.self) { line in
                                    Text("  ・\(line)")
                                        .font(.caption)
                                }
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }

                Button(model.dryRun ? "確認だけ実行" : "エンコードを実行") {
                    model.run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobRunner.isRunning || !model.folderExists)

                JobLogSectionView(kind: .encode)
            }
            .padding(20)
        }
    }
}
