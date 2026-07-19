import SwiftUI

enum AppTab: String, CaseIterable {
    case library = "ライブラリ"
    case romBrowser = "ROM"
    case controller = "コントローラー"

    var iconName: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .romBrowser: return "folder.fill"
        case .controller: return "gamecontroller.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var emulator: EmulatorViewModel
    @State private var selectedTab: AppTab = .library

    var body: some View {
        Group {
            if emulator.isRunning {
                ZStack(alignment: .topTrailing) {
                    EmulatorView(frame: emulator.currentFrame)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .background(.black)

                    if emulator.isPaused {
                        pauseOverlay
                    }

                    controlsOverlay
                }
            } else {
                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    switch selectedTab {
                    case .library:
                        LibraryView(scanner: emulator.scanner)
                    case .romBrowser:
                        ROMBrowserView()
                    case .controller:
                        ControllerSettingsView()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                Text("一時停止中")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("⌘P で再開 / Esc で停止")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var controlsOverlay: some View {
        HStack(spacing: 8) {
            Button(action: { emulator.togglePause() }) {
                Image(systemName: emulator.isPaused ? "play.fill" : "pause.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { emulator.stop() }) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .opacity(emulator.isPaused ? 1 : 0.3)
        .animation(.easeInOut(duration: 0.2), value: emulator.isPaused)
    }
}
