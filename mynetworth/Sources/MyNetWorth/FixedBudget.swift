import AppKit
import SwiftUI

// 固定収支タブ。mynetworth/2026_Sakata_支出表.md を軽量パースして表示する。
// 対応する記法は 見出し / 表 / 引用 / 区切り線 / 太字 だけ(このファイルで使う分)。
// リポジトリのファイルを直接読むので、md を編集して「再読込」を押せば反映される。
// リポジトリが見つからない場合はビルド時に同梱したコピーを表示する。
enum FixedBudgetFile {
    static let fileName = "2026_Sakata_支出表"
    static let sourceURL = URL(fileURLWithPath:
        NSString(string: "~/github/apps/mynetworth/\(fileName).md").expandingTildeInPath)

    struct Doc {
        var title: String
        var blocks: [MDBlock]
        var url: URL
        var modified: Date?
    }

    static func load() -> Doc? {
        var url = sourceURL
        var text = try? String(contentsOf: url, encoding: .utf8)
        if text == nil,
           let bundled = Bundle.main.url(forResource: fileName, withExtension: "md") {
            url = bundled
            text = try? String(contentsOf: bundled, encoding: .utf8)
        }
        guard let text else { return nil }
        var blocks = MDBlock.parse(text)
        var title = "固定収支"
        // 先頭の h1 はカードのタイトルに使い、本文からは外す。
        if case .heading(1, let t) = blocks.first?.kind {
            title = t
            blocks.removeFirst()
        }
        let modified = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        return Doc(title: title, blocks: blocks, url: url, modified: modified)
    }
}

struct MDBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case paragraph(String)
        case quote(String)
        case divider
        // trailing は列ごとの右寄せフラグ(区切り行の "---:" 判定)。
        case table(header: [String], trailing: [Bool], rows: [[String]])
    }

    let id: Int
    var kind: Kind

    static func parse(_ text: String) -> [MDBlock] {
        var kinds: [Kind] = []
        var para: [String] = []
        var table: [[String]] = []

        func flushPara() {
            if !para.isEmpty {
                kinds.append(.paragraph(para.joined(separator: "\n")))
                para = []
            }
        }
        func flushTable() {
            // ヘッダー行 + 区切り行 がそろって初めて表とみなす。
            if table.count >= 2 {
                kinds.append(.table(header: table[0],
                                    trailing: table[1].map { $0.hasSuffix(":") },
                                    rows: Array(table.dropFirst(2))))
            }
            table = []
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                flushPara()
                table.append(cells(line))
                continue
            }
            flushTable()
            if line.isEmpty {
                flushPara()
            } else if line == "---" {
                flushPara()
                kinds.append(.divider)
            } else if line.hasPrefix("#") {
                flushPara()
                let level = line.prefix(while: { $0 == "#" }).count
                kinds.append(.heading(level,
                    String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix(">") {
                flushPara()
                kinds.append(.quote(
                    String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                para.append(line)
            }
        }
        flushTable()
        flushPara()
        return kinds.enumerated().map { MDBlock(id: $0.offset, kind: $0.element) }
    }

    private static func cells(_ line: String) -> [String] {
        var s = line
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// **太字** などのインライン記法だけ AttributedString に任せる。
private func mdInline(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s)) ?? AttributedString(s)
}

struct FixedBudgetTab: View {
    @State private var doc: FixedBudgetFile.Doc?

    var body: some View {
        DashboardTab {
            if let doc {
                Card(title: doc.title) {
                    ForEach(doc.blocks) { block in
                        MDBlockView(kind: block.kind)
                    }
                    Divider().padding(.top, 4)
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.url.path)
                            if let m = doc.modified {
                                Text("更新: \(m.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            self.doc = FixedBudgetFile.load()
                        } label: {
                            Label("再読込", systemImage: "arrow.clockwise")
                        }
                        Button {
                            NSWorkspace.shared.open(doc.url)
                        } label: {
                            Label("ファイルを編集", systemImage: "square.and.pencil")
                        }
                    }
                }
            } else {
                Card(title: "固定収支") {
                    Text("\(FixedBudgetFile.fileName).md が見つかりません\n(\(FixedBudgetFile.sourceURL.path))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { doc = FixedBudgetFile.load() }
    }
}

struct MDBlockView: View {
    var kind: MDBlock.Kind

    var body: some View {
        switch kind {
        case .heading(let level, let text):
            if level <= 2 {
                Text(text)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            } else {
                Text(text)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        case .paragraph(let text):
            Text(mdInline(text))
                .font(.callout)
                .foregroundStyle(.secondary)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(width: 3)
                Text(mdInline(text))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .divider:
            Divider()
        case .table(let header, let trailing, let rows):
            MDTableView(header: header, trailing: trailing, rows: rows)
        }
    }
}

struct MDTableView: View {
    var header: [String]
    var trailing: [Bool]
    var rows: [[String]]

    private func alignment(_ i: Int) -> HorizontalAlignment {
        i < trailing.count && trailing[i] ? .trailing : .leading
    }

    private func cell(_ row: [String], _ i: Int) -> String {
        i < row.count ? row[i] : ""
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                ForEach(header.indices, id: \.self) { i in
                    Text(mdInline(header[i]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(alignment(i))
                }
            }
            Divider()
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(header.indices, id: \.self) { i in
                        Text(mdInline(cell(rows[r], i)))
                            .monospacedDigit()
                    }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 2)
    }
}
