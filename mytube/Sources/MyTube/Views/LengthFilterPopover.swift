import SwiftUI

/// トップバーの「長さ」ボタンから開く、動画の長さ(秒)を範囲指定するポップオーバー。
struct LengthFilterPopover: View {
    @Binding var minSecondsText: String
    @Binding var maxSecondsText: String
    let isMeasuring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("動画の長さで絞り込み")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("最小(秒)", text: $minSecondsText)
                    .frame(width: 80)
                    .onChange(of: minSecondsText) { newValue in
                        minSecondsText = newValue.filter(\.isNumber)
                    }
                Text("〜")
                    .foregroundStyle(.secondary)
                TextField("最大(秒)", text: $maxSecondsText)
                    .frame(width: 80)
                    .onChange(of: maxSecondsText) { newValue in
                        maxSecondsText = newValue.filter(\.isNumber)
                    }
            }
            .textFieldStyle(.roundedBorder)

            if isMeasuring {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("動画の長さを計測中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !minSecondsText.isEmpty || !maxSecondsText.isEmpty {
                Button("クリア") {
                    minSecondsText = ""
                    maxSecondsText = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 220)
    }
}
