import SwiftUI

struct DateEstimateView: View {
    @StateObject private var vm = DateEstimateViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("日付推定")
                    .font(.title2).bold()
                Text("撮影日が分からない写真(誤配置修正が退避させたUnknownフォルダ等)を、候補年のEXIF付き写真と見た目(顔検出+画像特徴量)で比較し、近い候補の日付を提示します。あくまで目安なので、候補のサムネイルと日付を見比べて選ぶか、手動で日付を指定してください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "対象フォルダ(日付不明の写真)", path: $vm.unknownFolderPath, exists: vm.unknownFolderExists, onPick: vm.pickUnknownFolder)
                FolderPickerRow(label: "ライブラリルート(年フォルダの親)", path: $vm.libraryRootPath, exists: vm.libraryRootExists, onPick: vm.pickLibraryRoot)

                if vm.years.isEmpty {
                    Text(vm.libraryRootExists ? "年フォルダ(YYYY)が見つかりません" : "フォルダが見つかりません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("候補年(参照元)").font(.headline)
                            Spacer()
                            Button("全選択") { vm.selectAllCandidateYears() }
                                .disabled(jobRunner.isRunning)
                            Button("全解除") { vm.selectNoneCandidateYears() }
                                .disabled(jobRunner.isRunning)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 4) {
                            ForEach(vm.years, id: \.self) { year in
                                Toggle(year, isOn: Binding(
                                    get: { vm.candidateYears.contains(year) },
                                    set: { on in
                                        if on { vm.candidateYears.insert(year) } else { vm.candidateYears.remove(year) }
                                    }
                                ))
                                .disabled(jobRunner.isRunning)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                Button {
                    vm.scan()
                } label: {
                    Label("スキャン開始", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobRunner.isRunning || !vm.unknownFolderExists || !vm.libraryRootExists || vm.candidateYears.isEmpty)

                JobLogSectionView(kind: .dateEstimate)

                if !vm.items.isEmpty {
                    Divider()
                    Text("候補 (\(vm.items.count) 件)")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.items) { item in
                            DateEstimateRow(vm: vm, item: item)
                        }
                    }
                }

                if !vm.applyLog.isEmpty {
                    Text("実行ログ")
                        .font(.headline)
                    LogConsoleView(lines: vm.applyLog)
                        .frame(height: 120)
                }
            }
            .padding(20)
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

private struct DateEstimateRow: View {
    @ObservedObject var vm: DateEstimateViewModel
    let item: DateEstimateItem
    @State private var manualDate = Date()
    @State private var showManualPicker = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                ThumbView(url: item.url, size: 110)
                Text(item.url.lastPathComponent)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 110)
            }

            if item.matches.isEmpty {
                Text("似た写真が見つかりませんでした")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(item.matches.enumerated()), id: \.offset) { _, match in
                            Button {
                                vm.apply(item, date: match.date)
                            } label: {
                                VStack(spacing: 2) {
                                    ThumbView(url: match.url, size: 80)
                                    Text(Self.dateFormatter.string(from: match.date))
                                        .font(.caption2)
                                    Text("距離 \(String(format: "%.2f", match.distance))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 90)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    showManualPicker.toggle()
                } label: {
                    Label("自分で日付を指定", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                if showManualPicker {
                    DatePicker("", selection: $manualDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    Button("この日付で移動") {
                        vm.apply(item, date: manualDate)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("スキップ") {
                    vm.skip(item)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor).opacity(0.4)))
    }
}

private struct ThumbView: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
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
        .frame(width: size, height: size)
        .clipped()
        .cornerRadius(6)
        .help(url.path)
        .onAppear {
            if image == nil {
                ThumbLoader.load(url) { image = $0 }
            }
        }
    }
}
