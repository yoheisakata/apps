import SwiftUI

/// トップメニュー(1段目): Nintendo(エミュレータ関連) / ボードゲーム
enum TopTab: String, CaseIterable {
    case nintendo = "Nintendo"
    case boardgames = "ボードゲーム"

    var iconName: String {
        switch self {
        case .nintendo: return "gamecontroller.fill"
        case .boardgames: return "checkerboard.rectangle"
        }
    }
}

/// Nintendo 選択時に2段目に出るサブメニュー
enum NintendoTab: String, CaseIterable {
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
    @State private var selectedTop: TopTab = .nintendo
    @State private var selectedNintendoTab: NintendoTab = .library

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
                    topTabBar
                    if selectedTop == .nintendo {
                        Divider()
                        nintendoSubTabBar
                    }
                    Divider()
                    switch selectedTop {
                    case .nintendo:
                        switch selectedNintendoTab {
                        case .library:
                            LibraryView(scanner: emulator.scanner)
                        case .romBrowser:
                            ROMBrowserView()
                        case .controller:
                            ControllerSettingsView()
                        }
                    case .boardgames:
                        BoardGamesRootView()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var topTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TopTab.allCases, id: \.self) { tab in
                Button(action: { selectedTop = tab }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTop == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundStyle(selectedTop == tab ? Color.accentColor : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Nintendo タブ選択時のみ2段目に出るサブメニュー(見た目はやや控えめ)
    private var nintendoSubTabBar: some View {
        HStack(spacing: 0) {
            ForEach(NintendoTab.allCases, id: \.self) { tab in
                Button(action: { selectedNintendoTab = tab }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.caption2)
                        Text(tab.rawValue)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(selectedNintendoTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundStyle(selectedNintendoTab == tab ? Color.accentColor : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
