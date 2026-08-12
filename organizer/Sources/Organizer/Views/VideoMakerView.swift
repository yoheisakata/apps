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

                TitleAndMusicSection(model: model)

                Divider()

                ClipSettingsSection(model: model)

                Divider()

                VolumeSettingsSection(model: model)

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

                if !model.videos.isEmpty {
                    Text("予想合計時間: 約 \(model.estimatedTotalDisplay)（タイトルカード・末尾の黒みを含む）")
                        .font(.callout)
                }

                HStack(spacing: 16) {
                    Button {
                        model.autoGenerate()
                    } label: {
                        Label("自動作成", systemImage: "wand.and.stars")
                    }
                    .disabled(!model.canAutoGenerate || jobRunner.isRunning)
                    .help("BGMの長さに合わせて、2〜3秒のクリップをフォルダ全体からバランスよく自動選択して作成します")

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

/// 「タイトル・BGM」セクション: 動画に付加するコンテンツ(タイトルカード・BGM)の設定。
/// 常に表示したままにするため(タブ切り替えで隠さない)、他のセクションと並べて表示する。
private struct TitleAndMusicSection: View {
    @ObservedObject var model: VideoMakerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("タイトル・BGM")
                .font(.headline)

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
                    if let durationDisplay = model.musicDurationDisplay {
                        Text("(\(durationDisplay))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.musicPath.isEmpty {
                        Button("クリア") { model.clearMusic() }
                    }
                    Button("選択…") { model.pickMusic() }
                }
            }
        }
    }
}

/// 「クリップ設定」セクション: 各クリップの抽出・結合・書き出しに関する設定。
private struct ClipSettingsSection: View {
    @ObservedObject var model: VideoMakerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("クリップ設定")
                .font(.headline)

            LabeledIntField(label: "1動画あたり", value: $model.clipSec, suffix: "秒")

            LabeledIntField(label: "上限ファイル数", value: $model.maxFileCount, suffix: "本")
                .onChange(of: model.maxFileCount) { _, _ in model.applyFileLimits() }
                .disabled(model.totalScannedCount <= 1)

            HStack {
                Text("ファイル再生の順序")
                Picker("", selection: $model.playOrder) {
                    ForEach(PlayOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .onChange(of: model.playOrder) { _, _ in model.applyFileLimits() }
            .disabled(model.videos.count <= 1)

            LabeledIntField(label: "冒頭スキップ", value: $model.offsetSec, suffix: "秒")

            LabeledDoubleField(label: "トランジション", value: $model.transitionSec, suffix: "秒")
                .disabled(model.videos.count <= 1)

            VStack(alignment: .leading, spacing: 2) {
                LabeledIntField(label: "画質 (CRF)", value: $model.qualityPreset)
                Text("18=高画質・大きい 〜 28=標準・小さい")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 「音量」セクション: BGM・元音声の音量バランス。
private struct VolumeSettingsSection: View {
    @ObservedObject var model: VideoMakerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("音量")
                .font(.headline)

            LabeledDoubleSlider(label: "BGM 音量", value: $model.bgmVolume, range: 0...1)
                .disabled(model.musicPath.isEmpty)

            LabeledDoubleSlider(label: "元音声 音量", value: $model.origVolume, range: 0...1)
        }
    }
}

/// 整数値をテキストフィールドで調整する行(スライダーは見づらいため持たない — 音量系のみスライダーを残す)。
private struct LabeledIntField: View {
    let label: String
    @Binding var value: Int
    var suffix: String = ""

    var body: some View {
        HStack {
            Text(label)
            TextField("", value: $value, format: .number)
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
            if !suffix.isEmpty {
                Text(suffix)
            }
        }
    }
}

/// 小数値をテキストフィールドで調整する行(スライダーは見づらいため持たない — 音量系のみスライダーを残す)。
private struct LabeledDoubleField: View {
    let label: String
    @Binding var value: Double
    var suffix: String = ""

    var body: some View {
        HStack {
            Text(label)
            TextField("", value: $value, format: .number.precision(.fractionLength(1...2)))
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
            if !suffix.isEmpty {
                Text(suffix)
            }
        }
    }
}

/// 音量系専用: スライダーとテキストフィールドの両方で調整できる行。
private struct LabeledDoubleSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix: String = ""

    var body: some View {
        HStack {
            Text(label)
            Slider(value: $value, in: range)
                .frame(width: 160)
            TextField("", value: $value, format: .number.precision(.fractionLength(1...2)))
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
            if !suffix.isEmpty {
                Text(suffix)
            }
        }
    }
}
