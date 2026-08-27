import Foundation

/// 「コナンメインストーリー」チャンネル(2026-08-22追加、「conanの動画の中で、メインストーリーが
/// あったらそれだけを抽出したリストを作ってほしい」という要望への対応。当初は汎用的に
/// 「メインストーリー」という名前だったが、同日中に「コナンメインストーリー」へ改名した
/// ― `Views/SidebarView.swift`参照)。「メインストーリー」=前編・後編/事件編・解決編の
/// ように、複数話にまたがって1つの話が続く回すべて、という定義(ユーザー確認済み ―
/// 黒の組織編に限らない)。各話に関連するキャラクター・組織名のタグ付けは
/// `Core/ConanEpisodeTags.swift`が別途担う。
///
/// 番組名・話数タグに関する外部データ(公式のエピソードリスト等)は一切持たない ―
/// **ファイル名の付け方そのものから**「連続する話数」を検出する純粋関数。conan専用ではなく、
/// `名探偵コナン - 0130 - 競技場無差別脅迫事件 - 前編.mp4`のような
/// 「番組名 - 話数 - タイトル[ - ラベル]」形式のファイル名であれば同じロジックがそのまま働く。
///
/// 判定ルール:
/// 0. `Entry.knownExceptionGroups`に載っている話数は無条件で対象に含める ― ルール1・2の
///    ロジックでは検出できないが、外部情報(Wikipedia本文の相互参照・ファンサイト記事)で
///    実在の連続話と確認済みの手動の例外リスト(2026-08-22追加、「メインストーリーはウィキ
///    とか確認した?」という指摘を受けて実際に確認した結果 ― 詳細は同プロパティのコメント
///    参照)。
/// 1. 話数トークン自体が範囲(`0309-311`のように`-`を含む)なら、それだけで1本のファイルが
///    複数話にまたがっている証拠なので無条件で対象に含める。
/// 2. それ以外は、同じ「ベースタイトル」(末尾の` - 前編`/`- 後編`等のラベル、末尾の全角
///    `（...）`、またはラベル無しでタイトルに直接続く末尾の数字を取り除いた残り)が完全一致
///    するか、区切りが無いタイトルどうしでも先頭3文字以上が共通する(緋色の序章/
///    緋色の追求/…、17年前の真相 血染めの騎士/…のように、区切り記号を使わず単なる
///    文字続きで連番と分かる回を拾うためのフォールバック)ペアが、話数として隣接
///    (連番、または話数トークンが同一)していれば両方を対象に含める。話数が数字でない
///    トークン(`Special`/`Movie`/`SP1`等)同士は、トークン文字列が完全一致すれば
///    「隣接」とみなす(数値の連番概念が無いため)。
///
/// **既知の限界**(他アプリの「既知の簡略化」と同じ位置づけ、`CLAUDE.md`参照): タイトルの
/// 先頭が3文字未満しか共通しない(見た目上まったく無関係に見える)連続ストーリーは、
/// ルール0に個別に追加しない限り検出できない。実際に0578〜0581(黒の組織・赤井家がらみの
/// 連続4話)・0705〜0706(バーボン編後半)の2件をWikipedia/ファンサイトで確認しルール0へ
/// 追加したが、**この2件はごく一部の例に過ぎない** ― conanライブラリの337本のうち
/// タイトルだけでは連続話と判定できなかった約104本を1本ずつ検証したわけではなく、
/// 疑わしい2本を抽出して調べたところ2本とも実際に連続話だった、という状況で止まっている。
/// つまり未検出の連続話はまだ他にも残っている可能性が高い ― 網羅的な検証には各話の原作
/// (コミックス)対応巻を突き合わせる必要があり、まだ行っていない。逆に、話数が隣接して
/// いてもタイトルのベース・接頭辞が一致しなければ「別の話」として除外される(実際に確認済み:
/// 0998/0999、1041/1042、1027/1028のような、たまたま隣接しているだけの無関係な単発回を
/// 誤って連結しない)。3文字という閾値は、conanライブラリの実データで単発回どうしの誤連結が
/// 起きないことを確認した上で選んでいる。
enum MainStoryDetector {
    /// `videos`(通常は`ContentView.allVideos`)から、「メインストーリー」に該当する動画の
    /// `stableKey`集合を返す。ソース・フォルダをまたいで判定する(番組名を問わずタイトルの
    /// 形だけで判定するため、無関係な動画が混ざっていても誤検出は極めて起きにくい ―
    /// ベースタイトルの完全一致まで要求しているため)。
    static func keys(in videos: [VideoItem]) -> Set<String> {
        let entries = videos.compactMap(Entry.init)
        guard !entries.isEmpty else { return [] }

        var includedKeys: Set<String> = []

        // ルール0: ファイル名からは判定できないが、外部情報(Wikipedia本文の相互参照・
        // ファンサイト記事)で実在の連続話と確認済みの例外(2026-08-22追加、「メインストーリーは
        // ウィキとか確認した?」という指摘を受けて実際に確認した結果)。`knownExceptionGroups`
        // 参照。
        for entry in entries {
            if let range = entry.numericRange, range.start == range.end,
               Entry.knownExceptionGroups.contains(where: { $0.contains(range.start) }) {
                includedKeys.insert(entry.stableKey)
            }
            // ユーザー提供の黒の組織中心「本筋」参照データ(2026-08-22追加、
            // `Core/ConanMainStoryReference.swift`参照)に載っている話数も無条件で含める。
            if let range = entry.numericRange, range.start <= range.end,
               ConanMainStoryReference.containsAnyEpisode(in: range.start...range.end) {
                includedKeys.insert(entry.stableKey)
            }
        }

        // ルール1: 話数トークン自体が範囲のものは無条件で含める。
        for entry in entries where entry.isRange {
            includedKeys.insert(entry.stableKey)
        }

        // ルール2: 同じベースタイトル×話数隣接のペアを総当たりで探す(数百本規模なら
        // O(n^2)でも実用上問題ない負荷 ― `ContentView`側でキャッシュして呼び出し頻度を
        // 抑える、下記`ContentView.rebuildMainStoryKeys()`参照)。
        for i in entries.indices {
            for j in entries.indices where j > i {
                let a = entries[i]
                let b = entries[j]
                guard a.sharesBase(with: b) else { continue }
                guard a.isAdjacent(to: b) else { continue }
                includedKeys.insert(a.stableKey)
                includedKeys.insert(b.stableKey)
            }
        }

        return includedKeys
    }

    /// ファイル名から話数トークン・ベースタイトルを読み取った1件分。
    private struct Entry {
        /// ルール0で使う、外部情報で確認済みの連続話グループ(話数の集合)。タイトルに
        /// 共通の接頭辞が一切無いため、ルール1・2のロジックでは検出できない実例のみを
        /// ここに手動で追加する ― 網羅的なリストではなく、ユーザーからの指摘を受けて
        /// 実際にWikipedia/ファンサイトで裏取りした分だけ。
        /// - `578〜581`: 「危機呼ぶ赤い前兆(オーメン)」「黒き13の暗示(サジェスト)」
        ///   「迫る黒の刻限(タイムリミット)」「赤く揺れる照準(ターゲット)」。黒の組織・
        ///   赤井家がらみの連続4話(DVD「赤井一家(ファミリー) TV SELECTION」でもまとめて
        ///   収録されている)。
        /// - `705〜706`: 「密室にいるコナン」「謎解きするバーボン」。安室=バーボン発覚直後の
        ///   「バーボン編の後半」で、原作(コミックス78巻 File.825-827)を2話に分けたもの
        ///   (ファンサイトで「705話/706話は連続」と明記されているのを確認)。
        static let knownExceptionGroups: [Set<Int>] = [
            [578, 579, 580, 581],
            [705, 706],
        ]

        let stableKey: String
        /// 話数トークン(例: `"0130"`, `"0309-311"`, `"Special"`)。
        let token: String
        /// `token`が数値として解釈できる場合の開始・終了(単一話なら同じ値)。
        let numericRange: (start: Int, end: Int)?
        /// ラベル(前編/後編等)・末尾の全角括弧・末尾の数字を取り除いた残りのタイトル。
        let base: String
        /// ラベルを取り除く前の生のタイトル本体(`sharesBase(with:)`の共通接頭辞フォールバック用)。
        let rawTail: String

        var isRange: Bool { numericRange.map { $0.start != $0.end } ?? false }

        init?(video: VideoItem) {
            // 「番組名 - 話数 - タイトル[ - ラベル...]」の形を想定。話数トークン自体が
            // 内部に`-`を持つ(`0309-311`)ことがあるが、` - `(前後に空白)で区切られる限り
            // 1トークンとしてそのまま残る。
            let components = video.title.components(separatedBy: " - ")
            guard components.count >= 3 else { return nil }
            let token = components[1]
            guard Entry.looksLikeEpisodeToken(token) else { return nil }

            self.stableKey = video.stableKey
            self.token = token
            self.numericRange = Entry.parseNumericRange(token)

            let tail = components[2...].joined(separator: " - ")
            self.rawTail = tail
            self.base = Entry.normalizeBase(tail)
        }

        /// ベースタイトルが完全一致すれば同じ話の一部とみなす。それに加えて、` - 前編`の
        /// ような明示的な区切りが一切無いタイトル同士(「緋色の序章」/「緋色の追求」/…、
        /// 「17年前の真相 血染めの騎士」/…のように、通常の空白だけで続き物と分かる回)を
        /// 拾うため、タイトル本体の共通接頭辞が一定の長さ(3文字)以上あればそれも
        /// 同じ話とみなすフォールバックを持つ(2026-08-22追加、実際のconanライブラリで
        /// 上記2つの実在する連続話がこのフォールバック無しでは検出できなかったため)。
        /// 3文字という閾値は、conanライブラリの単発回どうし(例:
        /// 「カーテンの向こう側」/「ケーキを愛する女のバラード」)が誤って連結されないことを
        /// 実データで確認した上で選んでいる(先頭1文字が偶然一致するだけの単発回は多いが、
        /// 3文字以上一致する無関係な単発回のペアは見つかっていない)。
        func sharesBase(with other: Entry) -> Bool {
            if !base.isEmpty, base == other.base { return true }
            return Entry.commonPrefixLength(rawTail, other.rawTail) >= 3
        }

        private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
            zip(a, b).prefix(while: ==).count
        }

        /// 数値どうしなら連番(差1以内)・範囲同士なら重なり/隣接、数値でなければトークン文字列の完全一致を「隣接」とみなす。
        func isAdjacent(to other: Entry) -> Bool {
            if let r1 = numericRange, let r2 = other.numericRange {
                return max(r1.start, r2.start) <= min(r1.end, r2.end) + 1
            }
            return numericRange == nil && other.numericRange == nil && token == other.token
        }

        /// 話数トークンらしい形かどうか: 数字(範囲含む)、または`Special`/`Movie`/`SP`+数字。
        private static func looksLikeEpisodeToken(_ token: String) -> Bool {
            if parseNumericRange(token) != nil { return true }
            if token == "Special" || token == "Movie" { return true }
            if token.hasPrefix("SP"), Int(token.dropFirst(2)) != nil { return true }
            return false
        }

        private static func parseNumericRange(_ token: String) -> (start: Int, end: Int)? {
            let parts = token.split(separator: "-")
            switch parts.count {
            case 1:
                guard let value = Int(parts[0]) else { return nil }
                return (value, value)
            case 2:
                guard let start = Int(parts[0]), let end = Int(parts[1]) else { return nil }
                return (start, end)
            default:
                return nil
            }
        }

        /// タイトル本体から「連続話であること」を示すラベル部分を取り除く。
        private static func normalizeBase(_ tail: String) -> String {
            // ` - ラベル` (前編/後編/事件編/解決編 等、最後の区切りだけ落とす)
            if let lastSeparatorRange = tail.range(of: " - ", options: .backwards) {
                return String(tail[tail.startIndex..<lastSeparatorRange.lowerBound])
            }
            // 末尾の全角括弧ラベル (探偵団VS強盗団（騒動） 等)
            if tail.hasSuffix("）"), let openRange = tail.range(of: "（", options: .backwards) {
                return String(tail[tail.startIndex..<openRange.lowerBound])
            }
            // 末尾に区切り無しで直接続く数字ラベル (ブラックインパクト1 等)
            if let lastNonDigitIndex = tail.lastIndex(where: { !$0.isNumber }),
               tail.index(after: lastNonDigitIndex) < tail.endIndex {
                return String(tail[tail.startIndex...lastNonDigitIndex])
            }
            return tail
        }
    }
}
