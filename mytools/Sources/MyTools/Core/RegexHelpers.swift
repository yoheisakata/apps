import Foundation

extension String {
    /// 最初にマッチした正規表現のキャプチャグループを返す（グループ0は全体マッチなので含まない）。
    /// マッチしなければ nil。空グループは "" になる。
    func firstMatchGroups(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        guard match.numberOfRanges > 1 else { return [] }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            guard let r = Range(match.range(at: i), in: self) else {
                groups.append("")
                continue
            }
            groups.append(String(self[r]))
        }
        return groups
    }

    func fullyMatches(_ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$") else { return false }
        let range = NSRange(startIndex..., in: self)
        return regex.firstMatch(in: self, range: range) != nil
    }
}
