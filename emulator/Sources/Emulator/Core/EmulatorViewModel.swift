import SwiftUI
import Combine

final class EmulatorViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var currentFrame: CGImage?
    @Published var errorMessage: String?

    @AppStorage("recentROMs") private var recentROMsData: Data = Data()

    let core = LibretroCore()
    let scanner = ROMScanner()
    private var cancellables = Set<AnyCancellable>()

    var recentROMs: [URL] {
        get {
            guard let urls = try? JSONDecoder().decode([String].self, from: recentROMsData) else { return [] }
            return urls.compactMap { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        set {
            let paths = newValue.prefix(10).map(\.path)
            recentROMsData = (try? JSONEncoder().encode(Array(paths))) ?? Data()
        }
    }

    init() {
        let audio = AudioEngine()
        let input = InputManager()
        core.audioEngine = audio
        core.inputManager = input
        input.onStop = { [weak self] in self?.stop() }

        core.$isRunning.receive(on: DispatchQueue.main).assign(to: &$isRunning)
        core.$isPaused.receive(on: DispatchQueue.main).assign(to: &$isPaused)
        core.$currentFrame.receive(on: DispatchQueue.main).assign(to: &$currentFrame)
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "ROMファイルを選択"
        panel.allowedContentTypes = [
            .init(filenameExtension: "nes")!,
            .init(filenameExtension: "sfc")!,
            .init(filenameExtension: "smc")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadROM(url: url)
    }

    func loadROM(url: URL) {
        errorMessage = nil

        let ext = url.pathExtension.lowercased()
        guard let corePath = findCore(for: ext) else {
            errorMessage = "対応するコアが見つかりません (\(ext))"
            return
        }

        do {
            try core.loadCore(at: corePath)
            try core.loadGame(at: url)
            core.loadSRAM()
            core.inputManager?.start()
            addToRecent(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePause() {
        core.togglePause()
    }

    func reset() {
        core.reset()
    }

    func stop() {
        core.inputManager?.stop()
        core.stop()
    }

    func saveState() {
        core.saveState()
    }

    func loadState() {
        core.loadState()
    }

    private func findCore(for ext: String) -> String? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let coresDir = appSupport.appendingPathComponent("RetroGames/Cores")

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: coresDir.path) else { return nil }
        let dylibs = files.filter { $0.hasSuffix(".dylib") }

        let nesPatterns = ["nestopia", "fceumm", "quicknes", "mesen"]
        let snesPatterns = ["snes9x", "bsnes", "mesen-s"]

        let patterns: [String]
        switch ext {
        case "nes": patterns = nesPatterns
        case "sfc", "smc": patterns = snesPatterns
        default: return nil
        }

        for pattern in patterns {
            if let match = dylibs.first(where: { $0.lowercased().contains(pattern) }) {
                return coresDir.appendingPathComponent(match).path
            }
        }

        return nil
    }

    private func addToRecent(_ url: URL) {
        var list = recentROMs
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        recentROMs = list
    }
}
