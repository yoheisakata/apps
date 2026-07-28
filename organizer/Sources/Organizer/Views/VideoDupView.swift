import SwiftUI
import UniformTypeIdentifiers

struct VideoDupView: View {
    @StateObject private var vm = VideoDupViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared
    @State private var dropTargeted = false
    @State private var confirmingTrash = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if vm.isWorking {
                ProgressView(value: vm.progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Divider()
            content
            Divider()
            bottomBar
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dropTargeted ? Color.accentColor : Color.clear, lineWidth: 3)
                .padding(3)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    }
                    if let url {
                        DispatchQueue.main.async { vm.addFolders([url]) }
                    }
                }
            }
            return true
        }
        .alert("エラー", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .confirmationDialog(
            "\(vm.selectedVideos.count) 本（\(ByteFmt.string(vm.selectedBytes))）をゴミ箱へ移動しますか？",
            isPresented: $confirmingTrash
        ) {
            Button("ゴミ箱へ移動", role: .destructive) { vm.trashSelected() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("完全には削除されません。ゴミ箱から復元できます。")
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    vm.openPanel()
                } label: {
                    Label("フォルダを追加", systemImage: "folder.badge.plus")
                }
                .disabled(vm.isWorking)

                if vm.isWorking {
                    Button("キャンセル") { vm.cancel() }
                } else {
                    Button {
                        if jobRunner.isRunning {
                            vm.errorMessage = "他の処理(\(jobRunner.title))を実行中です。完了してからもう一度お試しください。"
                        } else {
                            vm.scan()
                        }
                    } label: {
                        Label("スキャン", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.folders.isEmpty)
                }

                Picker("類似度", selection: $vm.matchLevel) {
                    ForEach(MatchLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(vm.isWorking)

                Spacer()
            }
            Text("拡張子を除いてファイル名が同じ動画、またはファイル名が違っても長さ(秒)が同じ動画を候補にし、開始5秒以内の数フレームで比較して同じ内容か確認します。キープするのはH.265の方(両方H.265/H.264ならサイズが大きい方)です。")
                .font(.caption)
                .foregroundColor(.secondary)
            if !vm.folders.isEmpty {
                HStack(spacing: 6) {
                    ForEach(vm.folders, id: \.self) { folder in
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                            Text(folder.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Button {
                                vm.removeFolder(folder)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.isWorking)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .help(folder.path)
                    }
                    Spacer()
                }
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        if vm.groups.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: vm.folders.isEmpty ? "film" : "checkmark.circle")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text(vm.folders.isEmpty
                     ? "動画の入ったフォルダをドラッグ＆ドロップ\nまたは「フォルダを追加」で選択してください"
                     : (vm.statusMessage.isEmpty ? "「スキャン」を押すと重複動画を探します" : vm.statusMessage))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(vm.groups.enumerated()), id: \.element.id) { index, group in
                        VideoDupGroupSection(vm: vm, group: group, number: index + 1)
                    }
                }
                .padding(12)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(vm.statusMessage)
                .foregroundColor(.secondary)
                .font(.callout)
            Spacer()
            Button("全グループ選択") {
                vm.enableAllGroups()
            }
            .disabled(vm.groups.isEmpty)
            Button("全グループ解除") {
                vm.disableAllGroups()
            }
            .disabled(vm.groups.isEmpty)
            Button("自動選択をやり直す") {
                vm.autoSelect()
            }
            .disabled(vm.groups.isEmpty)
            Button(role: .destructive) {
                if jobRunner.isRunning {
                    vm.errorMessage = "他の処理(\(jobRunner.title))を実行中です。完了してからもう一度お試しください。"
                } else {
                    confirmingTrash = true
                }
            } label: {
                Label("選択した \(vm.selectedVideos.count) 本をゴミ箱へ（\(ByteFmt.string(vm.selectedBytes))）",
                      systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.selection.isEmpty || vm.isWorking)
        }
        .padding(10)
    }
}

// MARK: - グループ表示

struct VideoDupGroupSection: View {
    @ObservedObject var vm: VideoDupViewModel
    let group: VideoDupGroup
    let number: Int

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 10)]

    private var isEnabled: Bool { vm.enabledGroups.contains(group.id) }
    private var keeperID: UUID? { group.keeper?.id }

    /// 重複写真パインと同じく、当たり判定を広く取ったカスタムチェックボックス。
    private var groupCheckbox: some View {
        HStack(spacing: 6) {
            Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .font(.body)
            Text("グループ \(number)")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { vm.setGroupEnabled(group, enabled: !isEnabled) }
        .help("クリックすると、このグループを削除対象から外す/含めるを切り替えます")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                groupCheckbox
                Text("\(group.videos.count) 本 · 最大 \(ByteFmt.string(group.wastedBytes)) 節約可能")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(group.videos) { video in
                    VideoDupCell(video: video, selected: vm.selection.contains(video.id), isKeeper: video.id == keeperID)
                        .onTapGesture { if isEnabled { vm.toggle(video) } }
                        .contextMenu {
                            Button("Finder で表示") {
                                NSWorkspace.shared.activateFileViewerSelecting([video.url])
                            }
                            Button("開く") {
                                NSWorkspace.shared.open(video.url)
                            }
                        }
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct VideoDupCell: View {
    let video: VideoCandidate
    let selected: Bool
    let isKeeper: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "video").foregroundColor(.secondary))
                    }
                }
                .frame(width: 170, height: 100)
                .clipped()
                .cornerRadius(6)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? .red : .white)
                    .shadow(radius: 2)
                    .padding(5)

                if isKeeper {
                    Text("残す")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green))
                        .foregroundColor(.white)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            Text(video.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 4) {
                Text(video.codec?.uppercased() ?? "不明")
                    .font(.caption2.bold())
                    .foregroundColor(video.isH265 ? .green : .orange)
                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(ByteFmt.string(video.fileSize))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 170)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.red.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.red : Color.clear, lineWidth: 2)
        )
        .help(video.url.path)
        .onAppear {
            if thumbnail == nil {
                VideoThumbLoader.load(video.url) { thumbnail = $0 }
            }
        }
    }
}
