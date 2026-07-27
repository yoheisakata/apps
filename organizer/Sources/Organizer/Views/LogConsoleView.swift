import SwiftUI

/// ジョブの標準出力を等幅フォントで流し込む共通ログビュー。末尾へ自動スクロールする。
struct LogConsoleView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: lines.count) { _, _ in
                guard let last = lines.indices.last else { return }
                withAnimation {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}
