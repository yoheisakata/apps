import SwiftUI
import UniformTypeIdentifiers

struct DupPhotosView: View {
    @StateObject private var vm = DupPhotosViewModel()
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
            "\(vm.selectedPhotos.count) 枚（\(ByteFmt.string(vm.selectedBytes))）をゴミ箱へ移動しますか？",
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
                        vm.scan()
                    } label: {
                        Label("スキャン", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.folders.isEmpty)
                }

                Picker("マッチレベル", selection: $vm.matchLevel) {
                    ForEach(MatchLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(vm.isWorking)

                Picker("", selection: $vm.keepRule) {
                    ForEach(KeepRule.allCases) { rule in
                        Text(rule.label).tag(rule)
                    }
                }
                .fixedSize()
                .disabled(vm.isWorking)

                Spacer()
            }
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
                Image(systemName: vm.folders.isEmpty ? "photo.on.rectangle.angled" : "checkmark.circle")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text(vm.folders.isEmpty
                     ? "写真の入ったフォルダをドラッグ＆ドロップ\nまたは「フォルダを追加」で選択してください"
                     : (vm.statusMessage.isEmpty ? "「スキャン」を押すと重複写真を探します" : vm.statusMessage))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(vm.groups.enumerated()), id: \.element.id) { index, group in
                        DupGroupSection(vm: vm, group: group, number: index + 1)
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
            Button("自動選択をやり直す") {
                vm.autoSelect()
            }
            .disabled(vm.groups.isEmpty)
            Button(role: .destructive) {
                confirmingTrash = true
            } label: {
                Label("選択した \(vm.selectedPhotos.count) 枚をゴミ箱へ（\(ByteFmt.string(vm.selectedBytes))）",
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

struct DupGroupSection: View {
    @ObservedObject var vm: DupPhotosViewModel
    let group: DupGroup
    let number: Int

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("グループ \(number)")
                    .font(.headline)
                Text(group.isExact ? "完全一致" : "類似")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(group.isExact ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
                Text("\(group.photos.count) 枚 · 最大 \(ByteFmt.string(group.wastedBytes)) 節約可能")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(group.photos) { photo in
                    DupPhotoCell(photo: photo, selected: vm.selection.contains(photo.id))
                        .onTapGesture { vm.toggle(photo) }
                        .contextMenu {
                            Button("Finder で表示") {
                                NSWorkspace.shared.activateFileViewerSelecting([photo.url])
                            }
                            Button("開く") {
                                NSWorkspace.shared.open(photo.url)
                            }
                        }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct DupPhotoCell: View {
    let photo: Photo
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    }
                }
                .frame(width: 150, height: 120)
                .clipped()
                .cornerRadius(6)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? .red : .white)
                    .shadow(radius: 2)
                    .padding(5)
            }
            Text(photo.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(photo.pixelWidth)×\(photo.pixelHeight) · \(ByteFmt.string(photo.fileSize))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 150)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.red.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.red : Color.clear, lineWidth: 2)
        )
        .help(photo.url.path)
        .onAppear {
            if image == nil {
                ThumbLoader.load(photo.url) { image = $0 }
            }
        }
    }
}
