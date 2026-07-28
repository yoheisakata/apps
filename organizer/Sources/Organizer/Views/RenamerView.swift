import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - メインビュー

struct RenamerView: View {
    @StateObject private var vm = RenamerViewModel()
    @State private var dropTargeted = false

    var body: some View {
        HSplitView {
            RulesPane(vm: vm)
                .frame(minWidth: 310, idealWidth: 340, maxWidth: 440)
            FilesPane(vm: vm, dropTargeted: $dropTargeted)
                .frame(minWidth: 480, maxWidth: .infinity)
        }
        .alert("エラー", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}

// MARK: - ルールペイン

private struct RulesPane: View {
    @ObservedObject var vm: RenamerViewModel
    @State private var showingSavePreset = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ルール")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("現在のルールを保存…") {
                        presetName = ""
                        showingSavePreset = true
                    }
                    .disabled(vm.rules.isEmpty)
                    if !vm.presets.isEmpty {
                        Divider()
                        ForEach(vm.presets) { preset in
                            Button(preset.name) { vm.applyPreset(preset) }
                        }
                        Divider()
                        Menu("削除") {
                            ForEach(vm.presets) { preset in
                                Button(preset.name) { vm.deletePreset(preset) }
                            }
                        }
                    }
                    Divider()
                    Button("書き出し…") { vm.exportPresets() }
                        .disabled(vm.presets.isEmpty)
                    Button("読み込み…") { vm.importPresets() }
                } label: {
                    Label("プリセット", systemImage: "star")
                }
                .menuStyle(.borderedButton)
                .fixedSize()
                Menu {
                    ForEach(RuleKind.allCases) { kind in
                        Button {
                            vm.addRule(kind)
                        } label: {
                            Label(kind.label, systemImage: kind.icon)
                        }
                    }
                } label: {
                    Label("追加", systemImage: "plus")
                }
                .menuStyle(.borderedButton)
                .fixedSize()
            }
            .padding(10)

            Divider()

            if vm.rules.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("「追加」からルールを作成してください")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($vm.rules) { $rule in
                            RuleCard(vm: vm, rule: $rule)
                        }
                    }
                    .padding(10)
                }
                Text("ルールは上から順に適用されます")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .alert("プリセットを保存", isPresented: $showingSavePreset) {
            TextField("プリセット名", text: $presetName)
            Button("保存") { vm.savePreset(named: presetName) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在のルール一式に名前を付けて保存します")
        }
    }
}

private struct RuleCard: View {
    @ObservedObject var vm: RenamerViewModel
    @Binding var rule: RenameRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Toggle("", isOn: $rule.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Label(rule.kind.label, systemImage: rule.kind.icon)
                    .font(.system(.body, weight: .semibold))
                Spacer()
                Button { vm.moveRule(rule.id, up: true) } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                Button { vm.moveRule(rule.id, up: false) } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                Button { vm.removeRule(rule.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Group {
                switch rule.kind {
                case .replace:
                    TextField("検索文字列", text: $rule.searchText)
                    TextField("置換文字列", text: $rule.replaceText)
                    HStack {
                        Toggle("正規表現", isOn: $rule.useRegex)
                        Toggle("大小同一視", isOn: $rule.caseInsensitive)
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption)
                case .addText:
                    TextField("追加するテキスト", text: $rule.insertText)
                    Picker("位置", selection: $rule.insertPosition) {
                        ForEach(InsertPosition.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if rule.insertPosition == .atIndex {
                        Stepper("挿入位置: \(rule.insertIndex) 文字目", value: $rule.insertIndex, in: 0...200)
                            .font(.caption)
                    }
                case .sequence:
                    Stepper("開始番号: \(rule.seqStart)", value: $rule.seqStart, in: 0...99999)
                    Stepper("増分: \(rule.seqStep)", value: $rule.seqStep, in: 1...100)
                    Stepper("桁数: \(rule.seqDigits)", value: $rule.seqDigits, in: 1...6)
                    TextField("区切り文字", text: $rule.seqSeparator)
                    Picker("位置", selection: $rule.seqPosition) {
                        Text("先頭").tag(InsertPosition.prefix)
                        Text("末尾").tag(InsertPosition.suffix)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                case .addDate:
                    Picker("日付", selection: $rule.dateSource) {
                        ForEach(DateSource.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    TextField("書式（例: yyyyMMdd）", text: $rule.dateFormat)
                    TextField("区切り文字", text: $rule.dateSeparator)
                    Picker("位置", selection: $rule.datePosition) {
                        Text("先頭").tag(InsertPosition.prefix)
                        Text("末尾").tag(InsertPosition.suffix)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if rule.dateSource == .exif {
                        Text("撮影日が取得できないファイルは変更されません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .insertMetadata:
                    Picker("項目", selection: $rule.metaField) {
                        ForEach(MetadataField.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    TextField("区切り文字", text: $rule.metaSeparator)
                    Picker("位置", selection: $rule.metaPosition) {
                        Text("先頭").tag(InsertPosition.prefix)
                        Text("末尾").tag(InsertPosition.suffix)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("音楽タグ (MP3/M4A等) と画像 (EXIF) に対応。取得できない場合は変更されません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .changeCase:
                    Picker("スタイル", selection: $rule.caseStyle) {
                        ForEach(CaseStyle.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                case .removeChars:
                    Stepper("削除する文字数: \(rule.removeCount)", value: $rule.removeCount, in: 1...100)
                    Picker("方向", selection: $rule.removeFrom) {
                        ForEach(RemoveFrom.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                case .truncate:
                    Stepper("残す文字数: \(rule.truncateKeep)", value: $rule.truncateKeep, in: 1...200)
                    Picker("残す位置", selection: $rule.truncateFrom) {
                        Text("先頭を残す").tag(RemoveFrom.start)
                        Text("末尾を残す").tag(RemoveFrom.end)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                case .cleanup:
                    Toggle("前後の空白を削除", isOn: $rule.cleanTrim)
                    Toggle("連続する空白を 1 つに", isOn: $rule.cleanCollapse)
                    Toggle("アンダースコアを空白に", isOn: $rule.cleanUnderscoreToSpace)
                    Toggle("空白をアンダースコアに", isOn: $rule.cleanSpaceToUnderscore)
                case .windowsSafe:
                    TextField("置換文字（空で削除）", text: $rule.winReplacement)
                    Text("< > : \" / \\ | ? * を置換し、末尾のドット・空白を削除します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .changeExtension:
                    TextField("新しい拡張子（空で削除）", text: $rule.newExtension)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.callout)
            .disabled(!rule.enabled)
            .opacity(rule.enabled ? 1 : 0.5)

            TextField("対象拡張子で絞り込み（例: jpg, png / 空=すべて）", text: $rule.filterExtensions)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .disabled(!rule.enabled)
                .opacity(rule.enabled ? 1 : 0.5)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - ファイルペイン

private struct FilesPane: View {
    @ObservedObject var vm: RenamerViewModel
    @Binding var dropTargeted: Bool
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        let previews = vm.previews()
        let changedCount = vm.items.filter { previews[$0.id]?.changed == true }.count
        let problemCount = vm.items.filter {
            let p = previews[$0.id]
            return p?.conflict == true || p?.invalid == true
        }.count

        VStack(spacing: 0) {
            HStack {
                Button {
                    vm.openPanel()
                } label: {
                    Label("ファイルを追加", systemImage: "plus")
                }
                Button("クリア") {
                    vm.items.removeAll()
                    vm.statusMessage = ""
                }
                .disabled(vm.items.isEmpty)
                Menu("並べ替え") {
                    Button("名前（昇順）") { vm.sortByName(ascending: true) }
                    Button("名前（降順）") { vm.sortByName(ascending: false) }
                    Divider()
                    Button("変更日（新しい順）") { vm.sortByDate(newestFirst: true) }
                    Button("変更日（古い順）") { vm.sortByDate(newestFirst: false) }
                }
                .fixedSize()
                .disabled(vm.items.isEmpty)
                Spacer()
                Text("\(vm.items.count) 件")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .padding(10)

            Divider()

            if vm.items.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("ここにファイルやフォルダをドラッグ＆ドロップ")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(vm.items) { item in
                        FileRow(item: item, preview: previews[item.id])
                            .contextMenu {
                                Button("リストから削除") {
                                    vm.items.removeAll { $0.id == item.id }
                                }
                            }
                    }
                    .onMove { from, to in
                        vm.items.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Menu {
                    Button("履歴ログを開く") { vm.openHistoryLog() }
                } label: {
                    Image(systemName: "clock")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if problemCount > 0 {
                    Label("\(problemCount) 件の名前が衝突しています", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.callout)
                } else {
                    Text(vm.statusMessage)
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button(vm.undoBatches.count > 1 ? "元に戻す（残り \(vm.undoBatches.count)）" : "元に戻す") {
                    vm.undo()
                }
                .disabled(vm.undoBatches.isEmpty)
                Button("リネーム実行（\(changedCount) 件）") {
                    if jobRunner.isRunning {
                        vm.errorMessage = "他の処理(\(jobRunner.title))を実行中です。完了してからもう一度お試しください。"
                    } else {
                        vm.performRename()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(changedCount == 0 || problemCount > 0)
            }
            .padding(10)
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
                        DispatchQueue.main.async {
                            vm.addURLs([url])
                        }
                    }
                }
            }
            return true
        }
    }
}

private struct FileRow: View {
    let item: FileItem
    let preview: PreviewEntry?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(item.isDirectory ? .cyan : .secondary)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let preview, preview.changed {
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                HStack(spacing: 4) {
                    if preview.conflict || preview.invalid {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    Text(preview.newName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(preview.conflict || preview.invalid ? .red : .accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
        .help(item.url.path)
    }
}
