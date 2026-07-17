import SwiftUI
import UniformTypeIdentifiers

struct ROMBrowserView: View {
    @EnvironmentObject var emulator: EmulatorViewModel
    @State private var dragOver = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("RetroGames")
                .font(.largeTitle.bold())

            Text("レトロゲームズ v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button(action: { emulator.openFilePanel() }) {
                    Label("ROMを開く…", systemImage: "doc.badge.plus")
                        .frame(width: 200)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Text("または ROM ファイルをここにドロップ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !emulator.recentROMs.isEmpty {
                Divider()
                    .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("最近開いたファイル")
                        .font(.headline)
                        .padding(.bottom, 4)

                    ForEach(emulator.recentROMs, id: \.self) { url in
                        Button(action: { emulator.loadROM(url: url) }) {
                            HStack {
                                Image(systemName: systemIcon(for: url))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Text(systemLabel(for: url))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: 400)
            }

            Spacer()

            if emulator.errorMessage != nil {
                Text(emulator.errorMessage!)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding()
            }

            coreStatusView
        }
        .frame(minWidth: 512, minHeight: 480)
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(dragOver ? Color.accentColor : .clear, lineWidth: 3)
        )
        .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    emulator.loadROM(url: url)
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var coreStatusView: some View {
        let coresDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RetroGames/Cores")
        let hasCores = (try? FileManager.default.contentsOfDirectory(atPath: coresDir.path)
            .contains { $0.hasSuffix(".dylib") }) ?? false

        if !hasCores {
            VStack(spacing: 4) {
                Text("コアが見つかりません")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("libretro コア (.dylib) を以下に配置してください:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(coresDir.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.bottom, 8)
        }
    }

    private func systemIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "nes": return "square.grid.3x3.fill"
        case "sfc", "smc": return "square.grid.4x3.fill"
        default: return "doc"
        }
    }

    private func systemLabel(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "nes": return "NES"
        case "sfc", "smc": return "SNES"
        default: return ext.uppercased()
        }
    }
}
