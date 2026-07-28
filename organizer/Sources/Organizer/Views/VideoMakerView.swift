import SwiftUI

struct VideoMakerView: View {
    @StateObject private var model = VideoMakerViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("まとめ動画")
                    .font(.title2).bold()
                Text("フォルダ内の動画から短いクリップを抜き出してつなぎ、タイトルカードとBGMを合成した1本のまとめ動画を作ります。暗い/止まったシーンは自動で避けます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "動画フォルダ", path: $model.folderPath, exists: model.folderExists, onPick: model.pickFolder)
                    .onChange(of: model.folderPath) { _, _ in model.refreshVideos() }

                if !model.videos.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(model.videos.count) 本の動画が見つかりました")
                            .font(.callout)

                        List(selection: $model.selectedVideos) {
                            ForEach(model.videos, id: \.self) { url in
                                Text(url.lastPathComponent).tag(url)
                            }
                        }
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack {
                            Text("クリックで選択して除外できます")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("選択した動画を除外") { model.removeSelected() }
                                .disabled(model.selectedVideos.isEmpty)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("タイトル")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("例: March, 2024（空欄でタイトルなし）", text: $model.titleText)
                            .textFieldStyle(.roundedBorder)
                        if !model.titleText.isEmpty {
                            Button("クリア") { model.titleText = "" }
                        }
                    }
                    if !model.titleText.isEmpty {
                        Text("冒頭に黒画面タイトルカード（3秒）＋映像中は左上に表示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("BGM ファイル（設定するとデフォルトとして記憶されます）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(model.musicPath.isEmpty ? "（なし）" : model.musicPath)
                            .foregroundStyle(model.musicPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !model.musicPath.isEmpty {
                            Button("クリア") { model.clearMusic() }
                        }
                        Button("選択…") { model.pickMusic() }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("詳細設定")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $model.durationMode) {
                        Text("1動画の抜粋秒数を指定").tag(DurationMode.clip)
                        Text("全体の尺を指定").tag(DurationMode.total)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    HStack(spacing: 20) {
                        if model.durationMode == .clip {
                            HStack {
                                Text("1動画あたり")
                                TextField("", value: $model.clipSec, format: .number)
                                    .frame(width: 56)
                                    .textFieldStyle(.roundedBorder)
                                Text("秒")
                            }
                            if !model.videos.isEmpty {
                                Text("→ 全体の尺：約 \(model.totalDisplay)")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack {
                                Text("全体の尺")
                                TextField("", value: $model.totalSec, format: .number)
                                    .frame(width: 64)
                                    .textFieldStyle(.roundedBorder)
                                Text("秒")
                            }
                            if !model.videos.isEmpty {
                                Text("→ 1動画あたり：約 \(model.clipDisplay)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    Toggle("ランダムモード", isOn: $model.randomMode)
                        .onChange(of: model.randomMode) { _, _ in model.applyFileLimits() }

                    HStack {
                        Toggle("上限ファイル数", isOn: $model.useMaxFileCount)
                            .onChange(of: model.useMaxFileCount) { _, _ in model.applyFileLimits() }
                        if model.useMaxFileCount {
                            TextField("", value: $model.maxFileCount, format: .number)
                                .frame(width: 56)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { model.applyFileLimits() }
                            Text("本")
                        }
                    }

                    Divider()

                    HStack {
                        Text("画質")
                        Picker("", selection: $model.qualityPreset) {
                            Text("高画質（ファイル大）").tag(18)
                            Text("標準").tag(23)
                            Text("小さいファイル").tag(28)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }

                    HStack {
                        Text("冒頭スキップ")
                        TextField("", value: $model.offsetSec, format: .number)
                            .frame(width: 56)
                            .textFieldStyle(.roundedBorder)
                        Text("秒")
                    }

                    HStack {
                        Text("トランジション")
                        Slider(value: $model.transitionSec, in: 0...2, step: 0.1)
                            .frame(width: 160)
                        Text(model.transitionSec == 0 ? "なし" : String(format: "%.1f秒", model.transitionSec))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }

                    HStack {
                        Text("BGM 音量")
                        Slider(value: $model.bgmVolume, in: 0...1)
                            .frame(width: 200)
                    }

                    HStack {
                        Text("元音声 音量")
                        Slider(value: $model.origVolume, in: 0...1)
                            .frame(width: 200)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("出力ファイル")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(model.outputPath.isEmpty ? "保存先を選択してください" : model.outputPath)
                            .foregroundStyle(model.outputPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("選択…") { model.pickOutput() }
                    }
                }

                HStack(spacing: 16) {
                    Button {
                        model.generate()
                    } label: {
                        Label("まとめ動画を作成", systemImage: "film")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.videos.isEmpty || model.outputPath.isEmpty || jobRunner.isRunning)

                    if !jobRunner.isRunning, FileManager.default.fileExists(atPath: model.outputPath) {
                        Button {
                            model.playOutput()
                        } label: {
                            Label("再生", systemImage: "play.circle.fill")
                        }
                        Button {
                            model.revealInFinder()
                        } label: {
                            Label("Finderで表示", systemImage: "folder")
                        }
                    }
                }

                JobLogSectionView(kind: .videoMaker)
            }
            .padding(20)
        }
        .onAppear { model.loadDefaults() }
        .confirmationDialog(
            "\(URL(fileURLWithPath: model.outputPath).lastPathComponent) は既に存在します。上書きしますか？",
            isPresented: $model.showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("上書きする", role: .destructive) {
                try? FileManager.default.removeItem(atPath: model.outputPath)
                model.startGenerate()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }
}
