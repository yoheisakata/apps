import SwiftUI

/// ジョブの標準出力を等幅フォントで流し込む共通ログビュー。末尾へ自動スクロールする。
struct LogConsoleView: View {
    let lines: [LogLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: lines.count) { _, _ in
                guard let last = lines.last else { return }
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}
