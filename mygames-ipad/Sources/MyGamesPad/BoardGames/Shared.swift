// Shared.swift — 全ゲーム共通の基盤(ゲーム種別、ルーター、セーブストア、配色、共通UI)

import Foundation
import SwiftUI

// MARK: - トランプ(pwa/cardgames)のゲーム一覧
//
// `Sources/MyGamesPad/CardGames/index.html`側の`goSetup(id)`が受け取るゲームID
// (`<id>-setup`という`.screen`のdiv)と1対1で対応させてある。トップページに
// トランプの8ゲームを個別アイコンとして並べるため(2026-09-09、ユーザー指示
// 「トランプの各ゲームをトップページにおいて」)、タップしたら`CardGamesWebView`
// 側でこのidを直接`goSetup()`に渡してホーム画面を経由せずセットアップ画面へ
// 直行させる。

struct CardGameEntry: Identifiable {
    let id: String
    let title: String
    let emblem: String
    /// `LauncherTheme.iconGradients`への固定インデックス。元々8種のトランプが
    /// この配列と同じ並び順(神経衰弱→ババ抜き→…→ブラックジャック)だったため
    /// 単純にループのindexを流用していたが、2026-09-09にババ抜き・7並べ・21を
    /// 削除して`all`から件数が減った際、以降の並びがずれて色がすべて隣の
    /// ゲームの色になってしまうのを避けるため、各ゲーム固有の色番号として
    /// 切り出した(値は元の並び順のまま、ババ抜きの1・7並べの4・21の5は欠番)。
    let colorIndex: Int

    static let all: [CardGameEntry] = [
        CardGameEntry(id: "shinkei", title: "神経衰弱", emblem: "🎴", colorIndex: 0),
        CardGameEntry(id: "speed", title: "スピード", emblem: "⚡", colorIndex: 2),
        CardGameEntry(id: "daifugo", title: "大富豪", emblem: "👑", colorIndex: 3),
        CardGameEntry(id: "poker", title: "ポーカー", emblem: "♠️", colorIndex: 6),
        CardGameEntry(id: "bj", title: "ブラックジャック", emblem: "🂡", colorIndex: 7),
    ]
}

// MARK: - ゲーム種別

enum GameKind: String, CaseIterable, Identifiable, Codable {
    case shogi       = "shogi"
    case chess       = "chess"
    case othello     = "othello"
    case go          = "go"
    case diamond     = "diamond"
    case gomoku      = "gomoku"
    case checkers    = "checkers"
    case connectFour = "connectFour"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shogi:       return "将棋"
        case .chess:       return "チェス"
        case .othello:     return "オセロ"
        case .go:          return "囲碁"
        case .diamond:     return "ダイヤモンドゲーム"
        case .gomoku:      return "五目並べ"
        case .checkers:    return "チェッカー"
        case .connectFour: return "コネクトフォー"
        }
    }

    var subtitle: String {
        switch self {
        case .shogi:       return "動けるマスのガイドとコーチ付きで学べる本格将棋"
        case .chess:       return "キャスリング・アンパッサン対応のチェス"
        case .othello:     return "角を取るのがコツ。定番のリバーシ"
        case .go:          return "9路盤から始める囲碁。囲んで取って地を作ろう"
        case .diamond:     return "跳び越しの連鎖で向かい側を目指すレースゲーム"
        case .gomoku:      return "先に5つ並べたら勝ち。いちばん手軽な入門ゲーム"
        case .checkers:    return "斜めに進んで飛び越えて取る。捕獲は必須ルール"
        case .connectFour: return "列に落として縦横斜め4つ並べたら勝ち"
        }
    }

    var emblem: String {
        switch self {
        case .shogi:       return "王"
        case .chess:       return "♞"
        case .othello:     return "●"
        case .go:          return "碁"
        case .diamond:     return "◆"
        case .gomoku:      return "五"
        case .checkers:    return "⛀"
        case .connectFour: return "4"
        }
    }
}

// MARK: - 画面遷移

enum Screen: Equatable {
    case menu
    case game(GameKind)
    /// トランプの特定の1ゲームへ直行する(`CardGameEntry.id`)。トップページに
    /// 個別のアイコンを並べているので、常に特定のゲームを指定して開く。
    case cardGames(String)
}

@MainActor
final class Router: ObservableObject {
    @Published var screen: Screen = .menu
    /// メニューのセーブ一覧を再読込させるためのトリガー
    @Published var saveVersion = 0

    func backToMenu() {
        screen = .menu
        #if os(iOS)
        // vs CPU/2人対戦の画面回転ロック(iPad版のみ)をメニューに戻るたび解除する
        OrientationLock.apply(.all)
        #endif
    }
    func open(_ kind: GameKind) { screen = .game(kind) }
    func openCardGames(_ id: String) { screen = .cardGames(id) }
    func bumpSaves() { saveVersion += 1 }
}

// MARK: - 難易度(チェス・オセロ用。将棋は専用の AILevel を使う)

enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case easy   = "入門"
    case normal = "初級"
    case hard   = "中級"

    var id: String { rawValue }
}

// MARK: - 対戦相手(AI か、同じ画面での2人対戦か)

enum OpponentMode: String, CaseIterable, Identifiable, Codable {
    case ai    = "AI対戦"
    case human = "2人対戦"

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

    // コネクトフォーは黒/白の駒だと盤の色と紛らわしいため、2026-09-09に
    // ユーザー指示で青/黄に変更した(`Disc.black`/`Disc.white`という内部の
    // 型・変数名自体は共有enumなので変えていない)。
    static let connectFourBlue   = Color(red: 0.15, green: 0.35, blue: 0.85)
    static let connectFourYellow = Color(red: 0.98, green: 0.80, blue: 0.10)
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
                Label("その他のゲーム", systemImage: "chevron.left")
            }
            Spacer()
            Text(title).font(.headline)
        }
    }
}

/// 2人対戦フルスクリーンレイアウトの右上に固定表示する「ゲーム終了」ボタン。
/// 盤の下のスクロール領域に埋もれさせず、縦向き・横向きどちらでもスクロール
/// せず常に見える位置に置くための共通部品(2026-09-09、ユーザー指示
/// 「横モードでも縦モードでもゲーム終了ボタンが見えるようにして」)。
struct EndGameOverlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("ゲーム終了", systemImage: "xmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(12)
    }
}

/// 対戦相手をラジオボタンで選ばせる1行(vs CPU / 2人対戦 の選択肢に使う)
struct RadioRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 各ゲーム共通の「対局前セットアップ」画面: 対戦相手をラジオボタンで選び、
/// (AI対戦のときだけ)追加設定を出し、スタートボタンで`onStart`を呼ぶ。
struct GameSetupView<Extra: View>: View {
    let title: String
    let subtitle: String
    @Binding var mode: OpponentMode
    @ViewBuilder var extraSettings: () -> Extra
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GameTopBar(title: title)
            Spacer(minLength: 12)
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("対戦相手").font(.headline)
                    RadioRow(title: "vs CPU", isSelected: mode == .ai) { mode = .ai }
                    RadioRow(title: "2人対戦", subtitle: "同じ画面で交互に操作します",
                             isSelected: mode == .human) { mode = .human }
                }
                .frame(maxWidth: 380)

                if mode == .ai {
                    VStack(alignment: .leading, spacing: 8) {
                        extraSettings()
                    }
                    .frame(maxWidth: 380)
                }

                Button("スタート", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .font(.title3.bold())
            }
            .padding(32)
            Spacer(minLength: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 棋譜・記録欄(指し手の記録)。将棋の`ShogiKifuView`と同じ見た目・スクロール挙動を
/// 他の全ゲームでも使えるよう共通化したもの(2026-09-09、ユーザー指示
/// 「全部のゲームで棋譜は将棋のようにしてほしい」)。
struct MoveRecordView: View {
    let title: String
    let entries: [KifuEntry]

    var body: some View {
        GroupBox(title) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { entry in
                            Text("\(entry.id). \(entry.text)")
                                .font(.system(.callout, design: .monospaced))
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                .frame(minHeight: 100, maxHeight: .infinity)
                .onChange(of: entries.count) {
                    if let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
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
