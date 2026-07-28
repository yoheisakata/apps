import SwiftUI

struct MisplacedFixView: View {
    @StateObject private var model = MisplacedFixViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("誤配置修正")
                    .font(.title2).bold()
                Text("写真ライブラリのルート(年フォルダの親)を指定し、年単位または月単位で写真整理の日付判定をやり直します。撮影日がEXIF/メタデータ/フォルダ名/ファイル名のどこからも分からずmtimeまでフォールバックしたファイルは、誤った年月日フォルダを作らずルート直下のUnknownフォルダへ元のファイル名のまま退避します。件数が多いと時間がかかるため、年・月を選んで少しずつ実行してください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                FolderPickerRow(label: "対象ルート(ライブラリ直下)", path: $model.rootPath, exists: model.rootExists, onPick: model.pickRoot)

                Picker("単位", selection: $model.granularity) {
                    Text("年単位").tag(FixGranularity.year)
                    Text("月単位").tag(FixGranularity.month)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .disabled(jobRunner.isRunning)

                if model.years.isEmpty {
                    Text(model.rootExists ? "年フォルダ(YYYY)が見つかりません" : "フォルダが見つかりません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(model.granularity == .month ? "対象の年(月の絞り込み)" : "対象の年").font(.headline)
                            Spacer()
                            Button("全選択") { model.selectAll() }
                                .disabled(jobRunner.isRunning)
                            Button("全解除") { model.selectNone() }
                                .disabled(jobRunner.isRunning)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 4) {
                            ForEach(model.years, id: \.self) { year in
                                Toggle(year, isOn: Binding(
                                    get: { model.selectedYears.contains(year) },
                                    set: { on in
                                        if on { model.selectedYears.insert(year) } else { model.selectedYears.remove(year) }
                                    }
                                ))
                                .disabled(jobRunner.isRunning)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                if model.granularity == .month {
                    if model.selectedYears.isEmpty {
                        Text("月を選ぶには、まず対象の年を選んでください")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.months.isEmpty {
                        Text("月フォルダ(MM)が見つかりません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("対象の月").font(.headline)
                                Spacer()
                                Button("全選択") { model.selectAllMonths() }
                                    .disabled(jobRunner.isRunning)
                                Button("全解除") { model.selectNoneMonths() }
                                    .disabled(jobRunner.isRunning)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 4) {
                                ForEach(model.months, id: \.self) { ym in
                                    Toggle(ym, isOn: Binding(
                                        get: { model.selectedMonths.contains(ym) },
                                        set: { on in
                                            if on { model.selectedMonths.insert(ym) } else { model.selectedMonths.remove(ym) }
                                        }
                                    ))
                                    .disabled(jobRunner.isRunning)
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }

                Toggle("EXIFが無い写真を類似写真から推定", isOn: $model.similarityFallbackEnabled)
                    .disabled(jobRunner.isRunning)

                if model.similarityFallbackEnabled {
                    Text("見た目が近い写真の日付を借用して移動します。誤判定のリスクがあるため、まず確認のみ/Dry runで「類似元」を確認してから修正実行してください。")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    if model.years.isEmpty {
                        Text("候補年にできるフォルダがありません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("候補年(参照元)").font(.headline)
                                Spacer()
                                Button("全選択") { model.selectAllCandidateYears() }
                                    .disabled(jobRunner.isRunning)
                                Button("全解除") { model.selectNoneCandidateYears() }
                                    .disabled(jobRunner.isRunning)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 4) {
                                ForEach(model.years, id: \.self) { year in
                                    Toggle(year, isOn: Binding(
                                        get: { model.candidateYears.contains(year) },
                                        set: { on in
                                            if on { model.candidateYears.insert(year) } else { model.candidateYears.remove(year) }
                                        }
                                    ))
                                    .disabled(jobRunner.isRunning)
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
                    }

                    Picker("類似度", selection: $model.similarityMatchLevel) {
                        ForEach(MatchLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(jobRunner.isRunning)
                }

                Picker("モード", selection: $model.mode) {
                    Text("確認のみ").tag(VerifyMode.report)
                    Text("Dry run（修正内容を表示）").tag(VerifyMode.dryRun)
                    Text("修正実行").tag(VerifyMode.fix)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if model.mode == .fix {
                    Label("実際にファイルを移動・リネームします(選んだ\(model.granularity == .month ? "月" : "年")のみ)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    HStack {
                        Text("一度に修正する最大数")
                        Stepper(value: $model.maxFixCount, in: 1...100_000, step: 10) {
                            Text("\(model.maxFixCount) 件")
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .leading)
                        }
                        .disabled(jobRunner.isRunning)
                    }
                    .font(.callout)
                }

                Button(runButtonLabel) {
                    model.run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobRunner.isRunning || !model.rootExists || isSelectionEmpty)

                JobLogSectionView(kind: .misplacedFix)
            }
            .padding(20)
        }
    }

    private var isSelectionEmpty: Bool {
        model.granularity == .month ? model.selectedMonths.isEmpty : model.selectedYears.isEmpty
    }

    private var runButtonLabel: String {
        let unit = model.granularity == .month ? "月" : "年"
        return model.mode == .fix ? "選んだ\(unit)を修正" : "選んだ\(unit)を検証"
    }
}
