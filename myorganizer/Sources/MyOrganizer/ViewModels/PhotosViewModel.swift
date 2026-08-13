import Foundation
import AppKit

@MainActor
final class PhotosViewModel: ObservableObject {
    @Published var srcPath: String
    @Published var destPath: String
    @Published var dryRun = false

    static let photoExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "dng", "raw", "cr2", "nef", "arw", "gif",
    ]

    private static let defaultSrc = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/photos_export").path
    private static let defaultDest = "/Users/yohei/Library/CloudStorage/OneDrive-Personal/s-leo/photo"

    init() {
        srcPath = UserDefaults.standard.string(forKey: "photos.src") ?? Self.defaultSrc
        destPath = UserDefaults.standard.string(forKey: "photos.dest") ?? Self.defaultDest
    }

    func pickSrc() {
        guard let url = choose(chooseFiles: false) else { return }
        srcPath = url.path
        UserDefaults.standard.set(srcPath, forKey: "photos.src")
    }

    func pickDest() {
        guard let url = choose(chooseFiles: false) else { return }
        destPath = url.path
        UserDefaults.standard.set(destPath, forKey: "photos.dest")
    }

    private func choose(chooseFiles: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = chooseFiles
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    var sourceExists: Bool {
        FileManager.default.fileExists(atPath: srcPath)
    }

    var destExists: Bool {
        FileManager.default.fileExists(atPath: destPath)
    }

    func run() {
        UserDefaults.standard.set(srcPath, forKey: "photos.src")
        UserDefaults.standard.set(destPath, forKey: "photos.dest")

        let destRoot = URL(fileURLWithPath: destPath)
        if MediaOrganizer.looksLikeYearFolder(destRoot) {
            showYearFolderAlert(destName: destRoot.lastPathComponent)
            return
        }

        let config = OrganizerConfig(
            sourceRoot: URL(fileURLWithPath: srcPath),
            destRoot: destRoot,
            extensions: Self.photoExtensions,
            dateSources: [MediaDateResolver.fromSips],
            convertHEICToJPG: true,
            dryRun: dryRun
        )

        JobRunner.shared.run(kind: .photos, title: dryRun ? "写真整理 (DRY RUN)" : "写真整理") { handle in
            _ = try await MediaOrganizer.run(
                config: config,
                progress: { handle.appendLog($0) },
                setProgress: { handle.setProgress($0) },
                setDetail: { handle.setDetail($0) },
                checkCancel: { try Task.checkCancellation() }
            )
        }
    }
}
