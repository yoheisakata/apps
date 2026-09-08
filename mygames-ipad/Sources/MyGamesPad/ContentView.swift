import SwiftUI

enum RootTab: String, CaseIterable {
    case boardgames = "ボードゲーム"
    case cardgames = "トランプ"

    var iconName: String {
        switch self {
        case .boardgames: return "checkerboard.rectangle"
        case .cardgames: return "suit.spade.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: RootTab = .boardgames

    var body: some View {
        VStack(spacing: 0) {
            topTabBar
            Divider()
            switch selectedTab {
            case .boardgames:
                BoardGamesRootView()
            case .cardgames:
                CardGamesWebView()
            }
        }
    }

    private var topTabBar: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases, id: \.self) { tab in
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
}
