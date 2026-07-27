import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddTorrentView: View {
    @ObservedObject var engine: Aria2Engine
    @Environment(\.dismiss) private var dismiss
    @State private var magnetText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("torrent を追加")
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("マグネットリンク")
                    .font(.subheadline)
                TextField("magnet:?xt=urn:btih:...", text: $magnetText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addMagnet)
            }

            HStack {
                Button("キャンセル") { dismiss() }
                Spacer()
                Button("ファイルを選択…", action: pickTorrentFile)
                Button("追加") { addMagnet() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(magnetText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func addMagnet() {
        guard !magnetText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        engine.addMagnet(magnetText)
        dismiss()
    }

    private func pickTorrentFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                engine.addTorrentFile(at: url)
            }
            dismiss()
        }
    }
}
