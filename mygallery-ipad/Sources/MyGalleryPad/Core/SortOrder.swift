import Foundation

/// グリッドの並び替え順。mygallery(Mac版)の`SortOrder`(`main.swift`、`sortMenuEntries`)を
/// このアプリ向けに絞って移植したもの ― Mac版の画質順(`.qualityDesc`/`.qualityAsc`)は
/// Visionベースの画質スコアリング(ローカルファイル専用機能、このアプリには元々無い)に
/// 依存するため対象外にした(`CLAUDE.md`「なぜOneDriveだけなのか」参照)。日付/名前/
/// サイズの5種類のみ。
enum SortOrder: Int, CaseIterable, Identifiable {
    case dateDesc = 0
    case dateAsc = 1
    case name = 2
    case sizeDesc = 3
    case sizeAsc = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dateDesc: return "新しい順"
        case .dateAsc: return "古い順"
        case .name: return "名前順"
        case .sizeDesc: return "サイズが大きい順"
        case .sizeAsc: return "サイズが小さい順"
        }
    }

    var systemImage: String {
        switch self {
        case .dateDesc, .dateAsc: return "calendar"
        case .name: return "textformat"
        case .sizeDesc, .sizeAsc: return "arrow.up.arrow.down"
        }
    }

    /// Mac版の`SortOrder.isDateOrder`と同じ ― この順序で並んでいるときだけ、
    /// グリッドの年月区切り線(`Views/GridView.swift`)に意味がある。名前順/サイズ順の
    /// ときに日付でグルーピングしても表示順とグループが噛み合わないため出さない。
    var isDateOrder: Bool { self == .dateDesc || self == .dateAsc }

    /// Mac版の`SortOrder.showsFileSize`と同じ ― この順序のときは、サイズバッジの
    /// 表示トグル(`Settings.showSizeBadge`)の状態に関わらず強制的にサイズバッジを出す
    /// (`Views/GridView.swift`の`ThumbnailCell`参照)。
    var showsFileSize: Bool { self == .sizeDesc || self == .sizeAsc }

    /// `Settings.sortOrder`に保存されている現在値。
    static var current: SortOrder {
        get { Settings.sortOrder }
        set { Settings.sortOrder = newValue }
    }

    /// アイテム配列をこの順序で並べ替える。日付順は`MediaItem.capturedDate`
    /// (ファイル名から推測した撮影日、優先)→無ければ`modifiedDate`
    /// (OneDriveのアップロード/同期日時、フォールバック)の順で比較する ―
    /// mygallery(Mac版)の`PhotoItem.sortDate`(ファイル名優先)と同じ考え方。
    /// Mac版は時刻(`HHMMSS`)まで見る`dateTime(from:)`を使うが、このアプリの
    /// `FilenameDateParser`は日付までしか拾わない(`Core/FilenameDateParser.swift`、
    /// `MediaItem.capturedDate`が元々その粒度で実装済み)ため、同日内の順序は
    /// `modifiedDate`のタイブレークに委ねる ― 時刻粒度のパーサーを新設するほどの
    /// 必要性は無いと判断した意図的な簡略化。
    func sorted(_ items: [MediaItem]) -> [MediaItem] {
        switch self {
        case .dateDesc:
            return items.sorted { sortKey($0) > sortKey($1) }
        case .dateAsc:
            return items.sorted { sortKey($0) < sortKey($1) }
        case .name:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .sizeDesc:
            return items.sorted { $0.size > $1.size }
        case .sizeAsc:
            return items.sorted { $0.size < $1.size }
        }
    }

    private func sortKey(_ item: MediaItem) -> (Date, Date) {
        // (撮影日, 更新日時)のタプルで比較する ― 撮影日が同じ(または両方無い)アイテム
        // どうしのタイブレークに更新日時を使う。
        (item.capturedDate ?? .distantPast, item.modifiedDate ?? .distantPast)
    }
}

private func < (a: (Date, Date), b: (Date, Date)) -> Bool {
    a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
}
private func > (a: (Date, Date), b: (Date, Date)) -> Bool {
    a.0 != b.0 ? a.0 > b.0 : a.1 > b.1
}
