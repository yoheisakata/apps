import SwiftUI

/// 起動直後のホーム画面。OneDriveリンクは`ContentView`にハードコードされた固定配列
/// (追加・削除UIは無し)。**年別フォルダのチェックリストもハードコード(`HardcodedLink.
/// availableFolders`)で、OneDriveのスキャンは行わない**(2026-08-29、「写真は2020から
/// 2026までチェックボックスを決め打ちにして。動画は2020から2021に。リンクからはとらない」
/// という要望への対応) ― そのため起動直後からチェックボックスが即座に表示される
/// (読み込み待ちが無い)。実際にOneDriveへ写真・動画を取得しに行くのは「スライドショー
/// 開始」を押した瞬間だけなので、この画面の`isLoading`/`errorMessage`はその取得中/
/// 失敗時にだけ意味を持つ。年別フォルダのチェックリストはリンクごとに独立したグループ
/// (「動画」「写真」という見出し付き)。**チェックボックスは`LazyVGrid`(可変列数)で
/// 横方向に並べ、折り返す**(2026-08-29、「チェックボックスをバランスよく並べて。
/// 横並びでOK」という要望への対応 ― 以前は1列の縦並びで、「写真」の7個(2020〜2026)が
/// 縦に間延びして見えていた)。各グループには「全選択」/「全非選択」ボタンも付けてある
/// (同じ要望内の「全選択、全非選択を追加して」に対応)。スライドショー設定(写真の表示
/// 秒数/シャッフル/時間制限)と、画面最下部中央の「スライドショー開始」ボタンもこの
/// 1画面にある。
struct HomeView: View {
    let links: [HardcodedLink]
    /// キーは`HardcodedLink.id`。
    let selectedFolders: [String: Set<String>]
    /// 「スライドショー開始」を押してOneDriveへ実際に取得しに行っている間`true`。
    let isLoading: Bool
    let errorMessage: String?
    @Binding var photoDuration: Double
    @Binding var shuffleEnabled: Bool
    /// スライドショー全体の時間制限(分)。`nil`は無制限。
    @Binding var timeLimitMinutes: Int?
    /// 表示モード(ウィンドウ内/全画面/PIP、2026-08-30追加)。
    @Binding var playbackMode: PlaybackMode
    let onToggleFolder: (HardcodedLink, String) -> Void
    let onSetAllFolders: (HardcodedLink, Bool) -> Void
    let onStart: () -> Void

    /// 時間制限スライダーの刻み: 5分刻みで5〜60分、最後の1つは「無制限」(`nil`)。
    /// 「スライダーで5分毎のメモリで最大は無制限」という要望どおり、スライダーの
    /// 右端(最大)が無制限を表す。
    private static let timeLimitOptions: [Int?] = stride(from: 5, through: 60, by: 5).map { $0 } + [nil]

    private var timeLimitIndex: Binding<Double> {
        Binding(
            get: { Double(Self.timeLimitOptions.firstIndex(of: timeLimitMinutes) ?? Self.timeLimitOptions.count - 1) },
            set: { newValue in
                let index = Int(newValue.rounded())
                timeLimitMinutes = Self.timeLimitOptions[min(max(index, 0), Self.timeLimitOptions.count - 1)]
            }
        )
    }

    private var timeLimitLabel: String {
        timeLimitMinutes.map { "\($0)分" } ?? "無制限"
    }

    private var canStart: Bool {
        !isLoading && links.contains { !(selectedFolders[$0.id] ?? Set($0.availableFolders)).isEmpty }
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            ForEach(links) { link in
                linkSection(link)
            }

            if isLoading {
                ProgressView("読み込み中…")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            GroupBox("スライドショー設定") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("ランダム再生", isOn: $shuffleEnabled)

                    Picker("表示モード", selection: $playbackMode) {
                        ForEach(PlaybackMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("写真の表示時間")
                        Slider(value: $photoDuration, in: 3...15, step: 1)
                        Text("\(Int(photoDuration))秒")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("時間制限")
                        Slider(value: timeLimitIndex, in: 0...Double(Self.timeLimitOptions.count - 1), step: 1)
                        Text(timeLimitLabel)
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 8)

            Button("スライドショー開始", action: onStart)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
                .disabled(!canStart)
        }
        .padding(24)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("MySlideshow")
                .font(.title2.weight(.bold))
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func linkSection(_ link: HardcodedLink) -> some View {
        GroupBox(link.name) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button("全選択") { onSetAllFolders(link, true) }
                    Button("全非選択") { onSetAllFolders(link, false) }
                    Spacer()
                }
                .font(.caption)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], alignment: .leading, spacing: 6) {
                    ForEach(link.availableFolders, id: \.self) { folder in
                        Toggle(folder, isOn: Binding(
                            get: { (selectedFolders[link.id] ?? Set(link.availableFolders)).contains(folder) },
                            set: { _ in onToggleFolder(link, folder) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isLoading)
    }
}
