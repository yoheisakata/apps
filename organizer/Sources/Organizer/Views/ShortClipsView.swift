import SwiftUI

struct ShortClipsView: View {
    @StateObject private var model = ShortClipsViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("短い動画検索")
                    .font(.title2).bold()
                Text("フォルダ内の動画から指定秒数以下のものを洗い出します。誤操作で撮れた一瞬の動画の整理などに。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "対象フォルダ", path: $model.folderPath, exists: model.folderExists, onPick: model.pickFolder)

                HStack {
                    Text("閾値")
                    Slider(value: $model.maxSeconds, in: 1...30, step: 1)
                        .frame(maxWidth: 240)
                    Text("\(Int(model.maxSeconds)) 秒以下")
                        .monospacedDigit()
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
                    Text("\(model.clips.count) 件見つかりました")
                        .font(.callout)
                    List(model.clips) { clip in
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
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                    .frame(minHeight: 140, maxHeight: 200)
                }

                JobLogSectionView(kind: .shortClips)
            }
            .padding(20)
        }
    }
}
