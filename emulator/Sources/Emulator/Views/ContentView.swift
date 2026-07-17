import SwiftUI

struct ContentView: View {
    @EnvironmentObject var emulator: EmulatorViewModel

    var body: some View {
        Group {
            if emulator.isRunning {
                ZStack(alignment: .topTrailing) {
                    EmulatorView(frame: emulator.currentFrame)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .background(.black)

                    if emulator.isPaused {
                        pauseOverlay
                    }

                    controlsOverlay
                }
            } else {
                ROMBrowserView()
            }
        }
        .frame(minWidth: 512, minHeight: 480)
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                Text("一時停止中")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("⌘P で再開")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var controlsOverlay: some View {
        HStack(spacing: 8) {
            Button(action: { emulator.togglePause() }) {
                Image(systemName: emulator.isPaused ? "play.fill" : "pause.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { emulator.stop() }) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .opacity(emulator.isPaused ? 1 : 0.3)
        .animation(.easeInOut(duration: 0.2), value: emulator.isPaused)
    }
}
