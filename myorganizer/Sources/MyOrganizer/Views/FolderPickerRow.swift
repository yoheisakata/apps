import SwiftUI

/// パス入力欄 + Finderで選ぶボタンの共通行。存在しないパスは赤く警告表示する。
struct FolderPickerRow: View {
    let label: String
    @Binding var path: String
    var exists: Bool
    var onPick: () -> Void
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                TextField(label, text: $path)
                    .textFieldStyle(.roundedBorder)
                Button("選択…", action: onPick)
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !exists {
                Label("フォルダが見つかりません（未マウントの可能性）", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
