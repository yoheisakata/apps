import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = VideoMakerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── フォルダ選択 ────────────────────────
            GroupBox(label: Label("動画フォルダ", systemImage: "folder")) {
                HStack {
                    Text(vm.folderPath.isEmpty ? "フォルダを選択してください" : vm.folderPath)
                        .foregroundColor(vm.folderPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("選択…") { vm.pickFolder() }
                }
                .padding(.top, 4)

                if !vm.videos.isEmpty {
                    Text("\(vm.videos.count) 本の動画が見つかりました")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .padding(.top, 2)

                    List(selection: $vm.selectedVideos) {
                        ForEach(vm.videos, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .tag(url)
                        }
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Text("クリックで選択して除外できます")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("選択した動画を除外") { vm.removeSelected() }
                            .disabled(vm.selectedVideos.isEmpty)
                    }
                }
            }

            // ── タイトル ────────────────────────────
            GroupBox(label: Label("タイトル", systemImage: "textformat")) {
                HStack {
                    TextField("例: March, 2024（空欄でタイトルなし）", text: $vm.titleText)
                        .textFieldStyle(.roundedBorder)
                    if !vm.titleText.isEmpty {
                        Button("クリア") { vm.titleText = "" }
                    }
                }
                .padding(.top, 4)
                if !vm.titleText.isEmpty {
                    Text("冒頭に黒画面タイトルカード（3秒）＋映像中は左上に表示")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }

            // ── BGM ────────────────────────────────
            GroupBox(label: Label("BGM ファイル（設定するとデフォルトとして記憶されます）", systemImage: "music.note")) {
                HStack {
                    Text(vm.musicPath.isEmpty ? "（なし）" : vm.musicPath)
                        .foregroundColor(vm.musicPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !vm.musicPath.isEmpty {
                        Button("クリア") { vm.clearMusic() }
                    }
                    Button("選択…") { vm.pickMusic() }
                }
                .padding(.top, 4)
            }

            // ── 詳細設定 ────────────────────────────
            GroupBox(label: Label("詳細設定", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 10) {

                    // 尺モード
                    Picker("", selection: $vm.durationMode) {
                        Text("1動画の抜粋秒数を指定").tag(DurationMode.clip)
                        Text("全体の尺を指定").tag(DurationMode.total)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 20) {
                        if vm.durationMode == .clip {
                            LabeledContent("1動画あたり") {
                                HStack {
                                    TextField("", value: $vm.clipSec, formatter: NumberFormatter())
                                        .frame(width: 56)
                                        .textFieldStyle(.roundedBorder)
                                    Text("秒")
                                }
                            }
                            if !vm.videos.isEmpty {
                                Text("→ 全体の尺：約 \(vm.totalDisplay)")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            LabeledContent("全体の尺") {
                                HStack {
                                    TextField("", value: $vm.totalSec, formatter: NumberFormatter())
                                        .frame(width: 64)
                                        .textFieldStyle(.roundedBorder)
                                    Text("秒")
                                }
                            }
                            if !vm.videos.isEmpty {
                                Text("→ 1動画あたり：約 \(vm.clipDisplay)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    Toggle("ランダムモード", isOn: $vm.randomMode)
                        .onChange(of: vm.randomMode) { vm.applyFileLimits() }

                    HStack {
                        Toggle("上限ファイル数", isOn: $vm.useMaxFileCount)
                            .onChange(of: vm.useMaxFileCount) { vm.applyFileLimits() }
                        if vm.useMaxFileCount {
                            TextField("", value: $vm.maxFileCount, formatter: NumberFormatter())
                                .frame(width: 56)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { vm.applyFileLimits() }
                            Text("本")
                        }
                    }

                    Divider()

                    LabeledContent("画質") {
                        Picker("", selection: $vm.qualityPreset) {
                            Text("高画質（ファイル大）").tag(18)
                            Text("標準").tag(23)
                            Text("小さいファイル").tag(28)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }

                    LabeledContent("冒頭スキップ") {
                        HStack {
                            TextField("", value: $vm.offsetSec, formatter: NumberFormatter())
                                .frame(width: 56)
                                .textFieldStyle(.roundedBorder)
                            Text("秒")
                        }
                    }

                    LabeledContent("トランジション") {
                        HStack {
                            Slider(value: $vm.transitionSec, in: 0...2, step: 0.1)
                                .frame(width: 160)
                            Text(vm.transitionSec == 0 ? "なし" : String(format: "%.1f秒", vm.transitionSec))
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)
                        }
                    }

                    LabeledContent("BGM 音量") {
                        Slider(value: $vm.bgmVolume, in: 0...1)
                            .frame(width: 200)
                    }

                    LabeledContent("元音声 音量") {
                        Slider(value: $vm.origVolume, in: 0...1)
                            .frame(width: 200)
                    }
                }
                .padding(.top, 4)
            }

            // ── 出力先 ──────────────────────────────
            GroupBox(label: Label("出力ファイル", systemImage: "square.and.arrow.down")) {
                HStack {
                    Text(vm.outputPath.isEmpty ? "保存先を選択してください" : vm.outputPath)
                        .foregroundColor(vm.outputPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("選択…") { vm.pickOutput() }
                }
                .padding(.top, 4)
            }

            // ── ステータス & 実行 ────────────────────
            if vm.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(vm.statusMessage)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(vm.progress * 100))%")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                }
            } else if !vm.statusMessage.isEmpty {
                Text(vm.statusMessage)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Spacer()
                Button(action: { vm.generate() }) {
                    Label("まとめ動画を作成", systemImage: "film")
                        .font(.title3.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.videos.isEmpty || vm.outputPath.isEmpty || vm.isRunning)

                if FileManager.default.fileExists(atPath: vm.outputPath) && !vm.isRunning {
                    Button(action: { vm.playOutput() }) {
                        Label("再生", systemImage: "play.circle.fill")
                            .font(.title3.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear { vm.loadDefaults() }
        .confirmationDialog(
            "\(URL(fileURLWithPath: vm.outputPath).lastPathComponent) は既に存在します。上書きしますか？",
            isPresented: $vm.showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("上書きする", role: .destructive) {
                try? FileManager.default.removeItem(atPath: vm.outputPath)
                vm.startGenerate()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("完成！", isPresented: $vm.showDone) {
            Button("▶ 再生") { vm.playOutput() }
            Button("Finderで表示") { vm.revealInFinder() }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("まとめ動画を保存しました:\n\(vm.outputPath)")
        }
        .alert("エラー", isPresented: $vm.showError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage)
        }
    }
}
