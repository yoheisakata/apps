import Foundation

struct ResolvedDate {
    let date: Date
    let source: String
}

/// 撮影日時を複数のソースから優先順位付きで解決する。
/// 一次ソース（EXIF/QuickTimeメタデータ）は写真・動画で異なるため呼び出し側が渡し、
/// フォルダ名/ファイル名/mtimeのフォールバックはここで共有する。
/// 優先順位はutilities/backup-photos.sh・backup-videos.shと同じ:
///   1. 一次ソース(EXIF/QuickTime) 2. mdls 3. フォルダ名 4. ファイル名 5. mtime
enum MediaDateResolver {
    private static let monthMap: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
        "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static var localCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    static func resolve(for url: URL, primarySources: [(URL) -> ResolvedDate?]) -> ResolvedDate {
        for source in primarySources {
            if let result = source(url) { return result }
        }
        if let result = fromMdls(url) { return result }
        if let result = fromFolderName(url) { return result }
        if let result = fromFileName(url.lastPathComponent) { return result }
        return fromModificationDate(url)
    }

    // MARK: - 3. フォルダ名パターン: "0517" / "May 17, 2025" / "Bellevue, May 31, 2026"

    static func fromFolderName(_ url: URL) -> ResolvedDate? {
        let parts = url.pathComponents

        for i in parts.indices.reversed() {
            let part = parts[i]
            // "0517"のようなMMDDフォルダは、その直接の親フォルダが年(西暦4桁)である場合だけ採用する。
            // パス中のどこかにある無関係な"20XX"フォルダと組み合わせてしまうと、実際の撮影日と無関係な
            // 日付を捏造してしまう(パス全体から独立に年とMMDDを探していた旧実装で実際に発生した)。
            if part.fullyMatches(#"(\d{2})(\d{2})"#), let g = part.firstMatchGroups(#"^(\d{2})(\d{2})$"#),
               let mm = Int(g[0]), let dd = Int(g[1]), (1...12).contains(mm), (1...31).contains(dd),
               i > 0, parts[i - 1].fullyMatches(#"20\d{2}"#), let year = Int(parts[i - 1]) {
                if let date = makeDate(year: year, month: mm, day: dd) {
                    return ResolvedDate(date: date, source: "フォルダ名(MMDD)")
                }
            }
            if let g = part.firstMatchGroups(#"([A-Za-z]+)\s+(\d{1,2}),?\s+(20\d{2})"#),
               g.count == 3, let month = monthMap[g[0].lowercased()], let day = Int(g[1]), let year = Int(g[2]) {
                if let date = makeDate(year: year, month: month, day: day) {
                    return ResolvedDate(date: date, source: "フォルダ名(英語)")
                }
            }
        }
        return nil
    }

    // MARK: - 4. ファイル名パターン: IMG_20260517_..., 2026_0517_...

    static func fromFileName(_ name: String) -> ResolvedDate? {
        let stem = (name as NSString).deletingPathExtension

        if let g = stem.firstMatchGroups(#"(20\d{2})_(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})"#), g.count == 6 {
            if let date = makeDate(year: Int(g[0]), month: Int(g[1]), day: Int(g[2]), hour: Int(g[3]), minute: Int(g[4]), second: Int(g[5])) {
                return ResolvedDate(date: date, source: "ファイル名")
            }
        }
        if let g = stem.firstMatchGroups(#"(20\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})"#), g.count == 6 {
            if let date = makeDate(year: Int(g[0]), month: Int(g[1]), day: Int(g[2]), hour: Int(g[3]), minute: Int(g[4]), second: Int(g[5])) {
                return ResolvedDate(date: date, source: "ファイル名")
            }
        }
        if let g = stem.firstMatchGroups(#"(20\d{2})(\d{2})(\d{2})"#), g.count == 3 {
            if let date = makeDate(year: Int(g[0]), month: Int(g[1]), day: Int(g[2])) {
                return ResolvedDate(date: date, source: "ファイル名")
            }
        }
        return nil
    }

    // MARK: - 5. mtime フォールバック

    static func fromModificationDate(_ url: URL) -> ResolvedDate {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        return ResolvedDate(date: date ?? Date(), source: "mtime")
    }

    /// sips/mdlsはスリープ復帰・外付けドライブの瞬断・大量連続実行時のプロセス起動失敗などで
    /// 一時的にエラーを返すことがある(数万枚を数時間かけて処理する整理ジョブで実際に発生し、
    /// 本来読めるはずのEXIF/メタデータがnil扱いになってフォルダ名フォールバックへ落ちる原因になった)。
    /// 1回だけ間を置いて再試行する。
    private static func execWithRetry(_ executable: String, _ arguments: [String]) -> String? {
        if let output = try? SyncExec.run(executable, arguments) { return output }
        Thread.sleep(forTimeInterval: 0.5)
        return try? SyncExec.run(executable, arguments)
    }

    // MARK: - 写真EXIF: sips -g creation

    static func fromSips(_ url: URL) -> ResolvedDate? {
        guard let output = execWithRetry("/usr/bin/sips", ["-g", "creation", url.path]) else { return nil }
        guard let g = output.firstMatchGroups(#"creation:\s*(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})"#), g.count == 6 else { return nil }
        guard let date = makeDate(year: Int(g[0]), month: Int(g[1]), day: Int(g[2]), hour: Int(g[3]), minute: Int(g[4]), second: Int(g[5])) else { return nil }
        return ResolvedDate(date: date, source: "EXIF(sips)")
    }

    // MARK: - コンテンツ作成日: mdls -name kMDItemContentCreationDate（UTC → ローカル変換）

    static func fromMdls(_ url: URL) -> ResolvedDate? {
        guard let output = execWithRetry("/usr/bin/mdls", ["-name", "kMDItemContentCreationDate", "-raw", url.path]) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "(null)", !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: trimmed) else { return nil }
        return ResolvedDate(date: date, source: "mdls")
    }

    // MARK: - 動画: ffprobeのQuickTimeメタデータ

    static func fromFfprobeQuickTime(_ url: URL) -> ResolvedDate? {
        guard let ffprobe = ToolLocator.resolve("ffprobe") else { return nil }
        guard let output = execWithRetry(ffprobe, ["-v", "quiet", "-print_format", "json", "-show_format", url.path]) else { return nil }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let tags = format["tags"] as? [String: Any] else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        if let s = tags["com.apple.quicktime.creationdate"] as? String,
           let date = iso.date(from: s) ?? isoNoFrac.date(from: s) {
            return ResolvedDate(date: date, source: "ffprobe(QT)")
        }
        if let s = tags["creation_time"] as? String {
            let normalized = s.hasSuffix("Z") ? s : s + "Z"
            if let date = iso.date(from: normalized) ?? isoNoFrac.date(from: normalized) {
                return ResolvedDate(date: date, source: "ffprobe(UTC)")
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func makeDate(year: Int?, month: Int?, day: Int?, hour: Int? = 0, minute: Int? = 0, second: Int? = 0) -> Date? {
        guard let year, let month, let day else { return nil }
        var comp = DateComponents()
        comp.year = year; comp.month = month; comp.day = day
        comp.hour = hour ?? 0; comp.minute = minute ?? 0; comp.second = second ?? 0
        return localCalendar.date(from: comp)
    }

}

extension Date {
    func formatted(_ pattern: String) -> String {
        let f = DateFormatter()
        f.dateFormat = pattern
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: self)
    }
}
