import AppKit
import SwiftUI

/// 実行ボタンの下に置く共通の実行ログセクション。タイトル/詳細/進捗/中止ボタン + ログ本文。
/// `kind`に対応するタブのログだけを表示する(ジョブはアプリ全体で同時に1本しか
/// 走らないが、ログはタブごとに独立して保持されるため、他タブの実行結果は混ざらない)。
struct JobLogSectionView: View {
    let kind: JobKind
    @ObservedObject private var jobRunner = JobRunner.shared

    private var isRunningThisKind: Bool {
        jobRunner.isRunning && jobRunner.currentKind == kind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRunningThisKind ? jobRunner.title : "実行ログ")
                        .font(.headline)
                    if isRunningThisKind, !jobRunner.detail.isEmpty {
                        Text(jobRunner.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if isRunningThisKind {
                    if let progress = jobRunner.progress {
                        ProgressView(value: progress)
                            .frame(width: 140)
                        Text("\(Int(progress * 100))%")
                            .font(.callout.monospacedDigit())
                            .frame(width: 40, alignment: .trailing)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button("中止") {
                        jobRunner.cancel()
                    }
                }
                Button {
                    let text = jobRunner.logLines(for: kind).map(\.text).joined(separator: "\n")
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }
                .disabled(jobRunner.logLines(for: kind).isEmpty)
            }

            LogConsoleView(lines: jobRunner.logLines(for: kind))
                .frame(height: 200)
        }
    }
}
