import SwiftUI
import GameController

struct ControllerSettingsView: View {
    @ObservedObject var config = ControllerConfig.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionSection
                mappingSection
                keyboardSection
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onDisappear { config.capturingFor = nil }
    }

    // MARK: - 接続状況

    private var connectionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if config.controllers.isEmpty {
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("コントローラーが接続されていません")
                            .foregroundStyle(.secondary)
                    }
                    Text("USB 接続後に認識されない場合は、一度抜き差ししてください。GameController フレームワーク対応のコントローラーのみ使用できます。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(config.controllers.enumerated()), id: \.offset) { _, controller in
                        HStack(spacing: 8) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text(controller.vendorName ?? "不明なコントローラー")
                            if controller.extendedGamepad == nil {
                                Text("(拡張ゲームパッド非対応)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Label("接続中のコントローラー", systemImage: "gamecontroller")
                .font(.headline)
        }
    }

    // MARK: - ボタン割り当て

    private var mappingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(RetroButton.displayOrder) { button in
                    HStack {
                        Text(button.displayName)
                            .font(.body.bold())
                            .frame(width: 60, alignment: .leading)
                        Text(config.physicalLabel(for: button.rawValue))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if config.capturingFor == button.rawValue {
                            Text("コントローラーのボタンを押してください…")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button("キャンセル") { config.capturingFor = nil }
                                .controlSize(.small)
                        } else {
                            Button("変更…") { config.capturingFor = button.rawValue }
                                .controlSize(.small)
                                .disabled(config.controllers.isEmpty || config.capturingFor != nil)
                        }
                    }
                    .padding(.vertical, 6)
                    if button != RetroButton.displayOrder.last {
                        Divider()
                    }
                }

                Divider().padding(.vertical, 4)

                HStack {
                    Text("十字キー・左スティックは移動に固定です")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("初期設定に戻す") { config.reset() }
                        .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(8)
        } label: {
            Label("ボタン割り当て", systemImage: "arrow.left.arrow.right")
                .font(.headline)
        }
    }

    // MARK: - キーボード操作(参考表示)

    private var keyboardSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                keyRow("移動", "矢印キー")
                keyRow("A / B", "Z / X")
                keyRow("X / Y", "A / S")
                keyRow("L / R", "Q / W")
                keyRow("Start / Select", "Return / 右Shift")
                keyRow("停止", "Esc または ⌘W")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Label("キーボード操作(固定)", systemImage: "keyboard")
                .font(.headline)
        }
    }

    private func keyRow(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(keys)
                .font(.body.monospaced())
        }
        .font(.caption)
    }
}
