import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var emulator: EmulatorViewModel
    @ObservedObject var thumbnails = ThumbnailLoader.shared
    @State private var searchText = ""
    @State private var selectedSystem: GameSystem? = nil
    @State private var selectedGenre: String? = nil

    private var filteredGames: [GameTitle] {
        var results = GameDatabase.search(searchText, system: selectedSystem)
        if let genre = selectedGenre {
            results = results.filter { $0.genre == genre }
        }
        return results
    }

    private var genres: [String] {
        let allGenres = Set(filteredGames.map(\.genre))
        return allGenres.sorted()
    }

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                if filteredGames.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredGames) { game in
                            GameCard(game: game, thumbnail: thumbnails.images[game.id])
                                .onAppear { thumbnails.loadThumbnail(for: game) }
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
            HStack {
                Text("\(filteredGames.count) タイトル")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.secondary)
                Text("ゲームライブラリ")
                    .font(.title2.bold())
                Spacer()

                TextField("タイトル検索…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }

            HStack(spacing: 8) {
                systemPicker
                genrePicker
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var systemPicker: some View {
        HStack(spacing: 4) {
            FilterChip(label: "すべて", isSelected: selectedSystem == nil) {
                selectedSystem = nil
                selectedGenre = nil
            }
            ForEach(GameSystem.allCases) { system in
                FilterChip(label: system.displayName, isSelected: selectedSystem == system) {
                    selectedSystem = system
                    selectedGenre = nil
                }
            }
        }
    }

    @ViewBuilder
    private var genrePicker: some View {
        if !genres.isEmpty {
            Divider()
                .frame(height: 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    FilterChip(label: "全ジャンル", isSelected: selectedGenre == nil) {
                        selectedGenre = nil
                    }
                    ForEach(genres, id: \.self) { genre in
                        FilterChip(label: genre, isSelected: selectedGenre == genre) {
                            selectedGenre = genre
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("該当するタイトルがありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

// MARK: - Game Card

struct GameCard: View {
    let game: GameTitle
    let thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)

                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: game.system == .nes ? "square.grid.3x3.fill" : "square.grid.4x3.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)

            VStack(spacing: 2) {
                Text(game.japanName)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 4) {
                    Text(game.system.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(game.system == .nes ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundStyle(game.system == .nes ? .red : .blue)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text("\(game.year)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(game.genre)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
    }
}
