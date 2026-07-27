import SwiftUI

private struct ToolStatus: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let path: String?
    let installHint: String?
}

struct PreflightView: View {
    @State private var refreshToken = UUID()

    private var tools: [ToolStatus] {
        _ = refreshToken
        return [
            ToolStatus(name: "ffmpeg", description: "動画のエンコード・コンテナ変換に必要", path: ToolLocator.resolve("ffmpeg"), installHint: "brew install ffmpeg"),
            ToolStatus(name: "ffprobe", description: "動画メタデータ・長さの取得に必要（ffmpegに同梱）", path: ToolLocator.resolve("ffprobe"), installHint: "brew install ffmpeg"),
            ToolStatus(name: "rsync", description: "同期機能に使用。Homebrew版は日本語ファイル名(NFD/NFC)対応が向上", path: ToolLocator.resolve("rsync"), installHint: "brew install rsync"),
            ToolStatus(name: "sips", description: "写真のEXIF取得・HEIC変換（macOS標準）", path: ToolLocator.resolve("sips"), installHint: nil),
            ToolStatus(name: "mdls", description: "コンテンツ作成日の取得（macOS標準）", path: ToolLocator.resolve("mdls"), installHint: nil),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("依存チェック")
                .font(.title2).bold()
            Text("Organizerはこれらの外部コマンドをそのまま呼び出します（同梱しません）。見つからない場合はHomebrewでインストールしてください。")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(tools) { tool in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: tool.path != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(tool.path != nil ? .green : .red)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.name).font(.headline)
                            Text(tool.description).font(.caption).foregroundStyle(.secondary)
                            if let path = tool.path {
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else if let hint = tool.installHint {
                                Text(hint)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(4)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }

            Button("再チェック") {
                ToolLocator.clearCache()
                refreshToken = UUID()
            }

            Spacer()
        }
        .padding(20)
    }
}
