import SwiftUI

/// 画面下部の共通ステータスバー。アプリ全体で1本しか走らないジョブの進捗と中止ボタンを出す。
struct StatusBarView: View {
    @ObservedObject var jobRunner: JobRunner

    var body: some View {
        if jobRunner.isRunning {
            HStack(spacing: 12) {
                if let progress = jobRunner.progress {
                    ProgressView(value: progress)
                        .frame(width: 140)
                    Text("\(Int(progress * 100))%")
                        .font(.callout.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(jobRunner.title)
                        .font(.callout)
                    if !jobRunner.detail.isEmpty {
                        Text(jobRunner.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !jobRunner.overallDetail.isEmpty {
                        Text("全体: \(jobRunner.overallDetail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Button("中止") {
                    jobRunner.cancel()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
