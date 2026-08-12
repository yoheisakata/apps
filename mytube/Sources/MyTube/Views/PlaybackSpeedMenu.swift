import SwiftUI

/// 再生速度(0.5x〜2.0x)を選ぶメニュー。YouTube の再生速度メニューと同じ刻み。
struct PlaybackSpeedMenu: View {
    @ObservedObject var engine: PlayerEngine

    private static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        Menu {
            ForEach(Self.speeds, id: \.self) { speed in
                Button {
                    engine.setPlaybackRate(speed)
                } label: {
                    if speed == engine.playbackRate {
                        Label(Self.label(for: speed), systemImage: "checkmark")
                    } else {
                        Text(Self.label(for: speed))
                    }
                }
            }
        } label: {
            Label(Self.label(for: engine.playbackRate), systemImage: "speedometer")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private static func label(for speed: Float) -> String {
        switch speed {
        case 0.5: return "0.5x"
        case 0.75: return "0.75x"
        case 1.0: return "標準"
        case 1.25: return "1.25x"
        case 1.5: return "1.5x"
        case 1.75: return "1.75x"
        case 2.0: return "2x"
        default: return "\(speed)x"
        }
    }
}
