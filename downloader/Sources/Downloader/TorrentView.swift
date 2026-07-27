import SwiftUI
import UniformTypeIdentifiers

struct TorrentView: View {
    @EnvironmentObject private var engine: Aria2Engine
    @State private var showAddSheet = false
    @State private var showSettingsSheet = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if !engine.toolsReady {
                bannerView("aria2 が見つかりません。ターミナルで `brew install aria2` を実行してください。")
            } else if let error = engine.lastError {
                bannerView(error)
            }

            if engine.torrents.isEmpty {
                Spacer()
                Text("torrent がありません。「追加」から magnet リンクや .torrent ファイルを追加するか、\nこのウィンドウに .torrent ファイルをドラッグ&ドロップしてください。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(engine.torrents) { torrent in
                    TorrentRow(torrent: torrent, engine: engine)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showAddSheet = true
                } label: {
                    Label("追加", systemImage: "plus")
                }
                .disabled(!engine.toolsReady)

                Button {
                    showSettingsSheet = true
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTorrentView(engine: engine)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(engine: engine)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private func bannerView(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color.orange)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "torrent" else { return }
                Task { @MainActor in
                    engine.addTorrentFile(at: url)
                }
            }
            handled = true
        }
        return handled
    }
}

private struct TorrentRow: View {
    let torrent: TorrentItem
    let engine: Aria2Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(torrent.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(torrent.isFetchingMetadata ? "メタデータ取得中…" : torrent.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if torrent.isFetchingMetadata {
                // ピアからメタデータ(ファイル構成・サイズ)を取得している段階。
                // DHT/トラッカーでピアが見つかるまで数秒〜十数秒かかることがあり、
                // 本体の進捗バーが出るまでの「ラグ」の正体はこれ。
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: torrent.progress)
            }

            HStack(spacing: 12) {
                if !torrent.isFetchingMetadata {
                    Label(formatSpeed(torrent.downloadSpeedBytes), systemImage: "arrow.down")
                    Label(formatSpeed(torrent.uploadSpeedBytes), systemImage: "arrow.up")
                    Text(String(format: "ratio %.2f", torrent.ratio))
                }
                Spacer()
                if torrent.status == "active" {
                    Button("一時停止") { engine.pause(torrent.gid) }
                } else if torrent.status == "paused" {
                    Button("再開") { engine.unpause(torrent.gid) }
                }
                Button("削除") { engine.remove(torrent.gid) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
