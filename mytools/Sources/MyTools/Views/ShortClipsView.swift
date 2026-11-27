import SwiftUI

struct ShortClipsView: View {
    @StateObject private var model = ShortClipsViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared
    @State private var confirmingTrash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("短い動画検索")
                    .font(.title2).bold()
                Text("フォルダ内の動画から指定秒数以下のものを洗い出します。誤操作で撮れた一瞬の動画の整理などに。結果をクリックすると再生できます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "対象フォルダ", path: $model.folderPath, exists: model.folderExists, onPick: model.pickFolder)

                HStack {
                    Text("閾値")
                    Slider(value: $model.maxSeconds, in: 0.1...30, step: 0.1)
                        .frame(maxWidth: 240)
                    TextField("秒", value: $model.maxSeconds, format: .number.precision(.fractionLength(0...2)))
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("秒以下")
                }

                HStack {
                    Button("検索") {
                        model.run()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jobRunner.isRunning || !model.folderExists)

                    if !model.clips.isEmpty {
                        Button("レポートを保存…") { model.saveReport() }
                        Button("プレイリストを保存…") { model.savePlaylist(andPlay: false) }
                        Button("プレイリストを保存して再生…") { model.savePlaylist(andPlay: true) }
                    }
                }

                if !model.clips.isEmpty {
                    HStack {
                        Text("\(model.clips.count) 件見つかりました")
                            .font(.callout)
                        Spacer()
                        Button("全選択") { model.selectAll() }
                        Button("選択解除") { model.deselectAll() }
                    }
                    List(model.clips) { clip in
                        ShortClipRow(model: model, clip: clip)
                    }
                    .frame(minHeight: 140, maxHeight: 260)

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            if jobRunner.isRunning {
                                model.errorMessage = "他の処理(\(jobRunner.title))を実行中です。完了してからもう一度お試しください。"
                            } else {
                                confirmingTrash = true
                            }
                        } label: {
                            Label("選択した \(model.selectedClips.count) 件をゴミ箱へ（\(String(format: "%.1f MB", model.selectedSizeMB)))",
                                  systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(model.selection.isEmpty)
                    }
                }

                JobLogSectionView(kind: .shortClips)
            }
            .padding(20)
        }
        .alert("エラー", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "\(model.selectedClips.count) 件（\(String(format: "%.1f MB", model.selectedSizeMB)))をゴミ箱へ移動しますか？",
            isPresented: $confirmingTrash
        ) {
            Button("ゴミ箱へ移動", role: .destructive) { model.trashSelected() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("完全には削除されません。ゴミ箱から復元できます。")
        }
    }
}

private struct ShortClipRow: View {
    @ObservedObject var model: ShortClipsViewModel
    let clip: ShortClip

    private var isSelected: Bool { model.selection.contains(clip.id) }

    var body: some View {
        HStack {
            Button {
                model.toggle(clip)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)

            Button {
                model.play(clip)
            } label: {
                HStack {
                    Text(String(format: "%.2f秒", clip.duration))
                        .monospacedDigit()
                        .frame(width: 70, alignment: .leading)
                    Text(String(format: "%.1f MB", clip.sizeMB))
                        .monospacedDigit()
                        .frame(width: 80, alignment: .leading)
                    Text(clip.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("クリックして再生")
        }
        .font(.system(.caption, design: .monospaced))
    }
}
