import SwiftUI

/// 上部バーの「キャッシュ」ボタンから開く、ローカルキャッシュの合計サイズ表示+上限設定+
/// 一括削除をまとめたポップオーバー(2026-08-05追加、「ローカルにキャッシュしたトータルを
/// 表示してほしい」「ローカルキャッシュの最大値を設定したい」という要望への対応 ―
/// 以前は「ローカルキャッシュを削除」という削除専用ボタン1つだけだった)。
struct CacheSettingsPopover: View {
    let totalBytes: Int64
    let fileCount: Int
    /// GB単位の上限を文字列で保持(`TopBarView`が`Settings.maxCacheBytes`との読み書きを担う ―
    /// `LengthFilterPopover`の秒数テキストと同じ「桁のフィルタだけここで行う」方針)。
    @Binding var maxCacheGBText: String
    let onDeleteAll: () -> Void
    let isDeleting: Bool

    private var totalSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ローカルキャッシュ")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("現在の合計サイズ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(fileCount > 0 ? "\(totalSizeText)(\(fileCount)件)" : "0 KB")
                    .font(.body.monospacedDigit())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("上限(GB) ― 超えたら古いものから自動削除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("5", text: $maxCacheGBText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: maxCacheGBText) { newValue in
                        maxCacheGBText = newValue.filter(\.isNumber)
                    }
            }

            Divider()

            Button(role: .destructive, action: onDeleteAll) {
                Label("すべて削除", systemImage: "trash")
            }
            .disabled(isDeleting || fileCount == 0)
        }
        .padding(16)
        .frame(width: 240)
    }
}
