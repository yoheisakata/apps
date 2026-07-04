import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var manager = DownloadManager()

    /// Video の解像度選択肢（px、すべて 720p 以上）。nil = 最高画質。
    private static let resolutionOptions: [(label: String, height: Int?)] = [
        ("720p", 720),
        ("1080p (フルHD)", 1080),
        ("1440p (2K)", 1440),
        ("2160p (4K)", 2160),
        ("最高画質", nil),
    ]

    @State private var url = ""
    @State private var wantAudio = true
    @State private var wantVideo = true
    @State private var videoHeight: Int? = 1080
    @State private var outputDir = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory())

    private var canDownload: Bool {
        manager.toolsReady && !manager.isRunning
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
            && (wantAudio || wantVideo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YouTube-downloader")
                .font(.title2).bold()

            if !manager.toolsReady {
                toolWarning
            }

            // URL 入力
            VStack(alignment: .leading, spacing: 6) {
                Text("YouTube のリンク").font(.subheadline).foregroundStyle(.secondary)
                TextField("https://www.youtube.com/watch?v=…", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            // 形式の選択
            VStack(alignment: .leading, spacing: 8) {
                Text("ダウンロードする形式").font(.subheadline).foregroundStyle(.secondary)
                Toggle(isOn: $wantAudio) {
                    VStack(alignment: .leading) {
                        Text("Audio（mp3・最高音質）")
                        Text("音声のみを mp3 で取得").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $wantVideo) {
                    VStack(alignment: .leading) {
                        Text("Video（mp4）")
                        Text("映像と最高音質の音声を結合").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("画質", selection: $videoHeight) {
                    ForEach(Self.resolutionOptions, id: \.label) { opt in
                        Text(opt.label).tag(opt.height)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
                .padding(.leading, 22)
                .disabled(!wantVideo)
            }

            // 保存先
            HStack {
                Text("保存先:").foregroundStyle(.secondary)
                Text(outputDir.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("変更…", action: chooseFolder)
            }
            .font(.subheadline)

            // 実行ボタン
            HStack {
                Button(action: download) {
                    Label("ダウンロード", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canDownload)

                if manager.isRunning {
                    Button("中止", role: .destructive, action: manager.cancel)
                }
            }

            // 進捗
            if manager.isRunning || manager.progress >= 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if manager.progress >= 0 {
                        ProgressView(value: min(manager.progress, 1))
                    } else {
                        ProgressView()
                    }
                    Text(manager.statusLine).font(.caption).foregroundStyle(.secondary)
                }
            }

            // ログ
            ScrollViewReader { sv in
                ScrollView {
                    Text(manager.log.isEmpty ? "ログはここに表示されます。" : manager.log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logEnd")
                }
                .frame(minHeight: 140)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: manager.log) { _ in
                    withAnimation { sv.scrollTo("logEnd", anchor: .bottom) }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 540)
    }

    private var toolWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("yt-dlp / ffmpeg が見つかりません", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).bold()
            Text("ターミナルで次を実行してインストールしてください:")
                .font(.caption)
            Text("brew install yt-dlp ffmpeg")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("yt-dlp: \(manager.ytdlpPath ?? "未検出")  /  ffmpeg: \(manager.ffmpegPath ?? "未検出")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func download() {
        var kinds: [DownloadKind] = []
        if wantVideo { kinds.append(.video) }
        if wantAudio { kinds.append(.audio) }
        manager.start(url: url, kinds: kinds, videoHeight: videoHeight, outputDir: outputDir)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDir
        if panel.runModal() == .OK, let dir = panel.url {
            outputDir = dir
        }
    }
}
