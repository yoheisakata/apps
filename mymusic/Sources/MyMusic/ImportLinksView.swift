import SwiftUI
import AppKit

/// 複数のリンクをテキストでまとめて貼り付け、1行1リンクとしてインポートするシート。
struct ImportLinksView: View {
    @ObservedObject var store: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("リンクをインポート")
                .font(.headline)
            Text("1行につき1リンクを貼り付けてください。")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .disabled(store.importProgress != nil)

            if let progress = store.importProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("インポート中… \(progress.done)/\(progress.total)")
                        .font(.caption)
                }
            }

            if let result = store.importResult {
                importResultView(result)
            }

            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                Button("インポート") {
                    store.importResult = nil
                    store.importLinks(text)
                    text = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.importProgress != nil)
            }
        }
        .padding()
        .frame(width: 440, height: 460)
    }

    @ViewBuilder
    private func importResultView(_ result: ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("成功 \(result.succeeded)件 / 失敗 \(result.failed.count)件")
                .font(.caption)
                .foregroundStyle(result.failed.isEmpty ? Color.secondary : Color.red)

            if !result.failed.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(result.failed.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.line).font(.caption2).lineLimit(1)
                                Text(item.message).font(.caption2).foregroundStyle(.red)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)

                Button("エラーログを Finder で表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.importErrorLogURL])
                }
                .font(.caption)
            }
        }
    }
}
