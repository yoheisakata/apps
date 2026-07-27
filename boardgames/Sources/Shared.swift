// Shared.swift — 全ゲーム共通の基盤(ゲーム種別、ルーター、セーブストア、配色、共通UI)

import Foundation
import SwiftUI

// MARK: - ゲーム種別

enum GameKind: String, CaseIterable, Identifiable, Codable {
    case shogi   = "shogi"
    case chess   = "chess"
    case othello = "othello"
    case go      = "go"
    case diamond = "diamond"
    case gomoku  = "gomoku"
    case mahjong = "mahjong"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shogi:   return "将棋"
        case .chess:   return "チェス"
        case .othello: return "オセロ"
        case .go:      return "囲碁"
        case .diamond: return "ダイヤモンドゲーム"
        case .gomoku:  return "五目並べ"
        case .mahjong: return "麻雀"
        }
    }

    var subtitle: String {
        switch self {
        case .shogi:   return "動けるマスのガイドとコーチ付きで学べる本格将棋"
        case .chess:   return "キャスリング・アンパッサン対応のチェス"
        case .othello: return "角を取るのがコツ。定番のリバーシ"
        case .go:      return "9路盤から始める囲碁。囲んで取って地を作ろう"
        case .diamond: return "跳び越しの連鎖で向かい側を目指すレースゲーム"
        case .gomoku:  return "先に5つ並べたら勝ち。いちばん手軽な入門ゲーム"
        case .mahjong: return "鳴きなしの入門ルールで打てる四人麻雀"
        }
    }

    var emblem: String {
        switch self {
        case .shogi:   return "王"
        case .chess:   return "♞"
        case .othello: return "●"
        case .go:      return "碁"
        case .diamond: return "◆"
        case .gomoku:  return "五"
        case .mahjong: return "中"
        }
    }
}

// MARK: - 画面遷移

enum Screen: Equatable {
    case menu
    case game(GameKind)
}

@MainActor
final class Router: ObservableObject {
    @Published var screen: Screen = .menu
    /// メニューのセーブ一覧を再読込させるためのトリガー
    @Published var saveVersion = 0

    func backToMenu() { screen = .menu }
    func open(_ kind: GameKind) { screen = .game(kind) }
    func bumpSaves() { saveVersion += 1 }
}

// MARK: - 難易度(チェス・オセロ用。将棋は専用の AILevel を使う)

enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case easy   = "入門"
    case normal = "初級"
    case hard   = "中級"

    var id: String { rawValue }
}

// MARK: - セーブ(各ゲーム 3 スロット)

struct SaveMeta: Codable {
    var savedAt: Date
    var title: String        // 例: "24手目 · 平手"
}

enum SaveStore {
    static let slotCount = 3

    private static var baseDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("BoardGames", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(game: GameKind, slot: Int) -> URL {
        let dir = baseDir.appendingPathComponent(game.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("slot\(slot).json")
    }

    static func save<T: Encodable>(_ value: T, game: GameKind, slot: Int) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            try data.write(to: url(game: game, slot: slot), options: .atomic)
            return true
        } catch {
            NSLog("save failed: \(error)")
            return false
        }
    }

    static func load<T: Decodable>(_ type: T.Type, game: GameKind, slot: Int) -> T? {
        guard let data = try? Data(contentsOf: url(game: game, slot: slot)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    /// メタ情報だけ読む(全ゲームのセーブ構造体は先頭に meta を持つ)
    private struct MetaEnvelope: Codable { var meta: SaveMeta }

    static func meta(game: GameKind, slot: Int) -> SaveMeta? {
        load(MetaEnvelope.self, game: game, slot: slot)?.meta
    }

    static func delete(game: GameKind, slot: Int) {
        try? FileManager.default.removeItem(at: url(game: game, slot: slot))
    }
}

// MARK: - 配色

enum Theme {
    static let boardWood   = Color(red: 0.93, green: 0.83, blue: 0.62)
    static let pieceWood   = Color(red: 0.98, green: 0.92, blue: 0.78)
    static let gridLine    = Color(red: 0.35, green: 0.25, blue: 0.15)
    static let target      = Color.green.opacity(0.45)
    static let selected    = Color.blue.opacity(0.35)
    static let lastMoveBg  = Color.yellow.opacity(0.35)
    static let hintBg      = Color.orange.opacity(0.5)
    static let promotedRed = Color(red: 0.75, green: 0.1, blue: 0.1)

    static let chessLight  = Color(red: 0.93, green: 0.89, blue: 0.80)
    static let chessDark   = Color(red: 0.63, green: 0.48, blue: 0.36)

    static let othelloFelt = Color(red: 0.10, green: 0.45, blue: 0.22)
}

// MARK: - 共通 UI 部品

/// サイドバー上部の共通バー(メニューに戻る)
struct GameTopBar: View {
    @EnvironmentObject var router: Router
    let title: String

    var body: some View {
        HStack {
            Button {
                router.backToMenu()
            } label: {
                Label("メニュー", systemImage: "chevron.left")
            }
            Spacer()
            Text(title).font(.headline)
        }
    }
}

/// ゲーム内の「途中保存」欄: 3 スロットへの保存とロード
struct SaveSlotsBox: View {
    @EnvironmentObject var router: Router
    let game: GameKind
    /// スロットへ保存する処理(成功なら true)
    let onSave: (Int) -> Bool
    /// スロットから読み込む処理(成功なら true)
    let onLoad: (Int) -> Bool

    @State private var flash: (slot: Int, text: String)?

    var body: some View {
        GroupBox("途中保存") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(1...SaveStore.slotCount, id: \.self) { slot in
                    slotRow(slot)
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func slotRow(_ slot: Int) -> some View {
        let meta = SaveStore.meta(game: game, slot: slot)
        HStack(spacing: 6) {
            Text("\(slot)")
                .font(.caption.bold())
                .frame(width: 14)
            Button("保存") {
                if onSave(slot) {
                    showFlash(slot, "保存しました")
                    router.bumpSaves()
                }
            }
            .controlSize(.small)
            Button("ロード") {
                if onLoad(slot) {
                    showFlash(slot, "ロードしました")
                }
            }
            .controlSize(.small)
            .disabled(meta == nil)
            if let flash, flash.slot == slot {
                Text(flash.text).font(.caption).foregroundStyle(.green)
            } else if let meta {
                Text(metaLabel(meta))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("空").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func showFlash(_ slot: Int, _ text: String) {
        flash = (slot, text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if flash?.slot == slot { flash = nil }
        }
    }

    private func metaLabel(_ meta: SaveMeta) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d HH:mm"
        return "\(meta.title) · \(fmt.string(from: meta.savedAt))"
    }
}
