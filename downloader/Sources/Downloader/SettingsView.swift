import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var engine: Aria2Engine
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Settings.downloadDirKey) private var downloadDir = Settings.defaultDownloadDir
    @AppStorage(Settings.maxUploadKBpsKey) private var maxUploadKBps = 50
    @AppStorage(Settings.maxDownloadKBpsKey) private var maxDownloadKBps = 0
    @AppStorage(Settings.seedRatioKey) private var seedRatio = 0
    @AppStorage(Settings.seedTimeMinutesKey) private var seedTimeMinutes = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("設定")
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("帯域制限(即時反映)")
                    .font(.headline)
                Text("ダウンロードを優先し、アップロードはほとんど行わないための設定です。0 は無制限を意味します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("アップロード上限 (KB/s)") {
                    TextField("", value: $maxUploadKBps, format: .number)
                        .frame(width: 80)
                        .onChange(of: maxUploadKBps) { _ in engine.applySpeedLimits() }
                }
                LabeledContent("ダウンロード上限 (KB/s)") {
                    TextField("", value: $maxDownloadKBps, format: .number)
                        .frame(width: 80)
                        .onChange(of: maxDownloadKBps) { _ in engine.applySpeedLimits() }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("保存先・シード設定(適用にはエンジンの再起動が必要)")
                    .font(.headline)

                HStack {
                    Text(downloadDir)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("変更…", action: pickDownloadDir)
                }

                LabeledContent("Seed ratio 上限(完了後)") {
                    TextField("", value: $seedRatio, format: .number)
                        .frame(width: 60)
                }
                LabeledContent("Seed time 上限(分、完了後)") {
                    TextField("", value: $seedTimeMinutes, format: .number)
                        .frame(width: 60)
                }
                Text("両方 0 のままだとダウンロード完了後すぐにシードを停止します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("保存して再起動") { engine.restart() }
            }

            Spacer()
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func pickDownloadDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: downloadDir)
        if panel.runModal() == .OK, let url = panel.url {
            downloadDir = url.path
        }
    }
}
