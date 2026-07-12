import SwiftUI
import AppKit
import UniformTypeIdentifiers

// レシートタブ。上部のセグメントで「一覧」(取り込み・編集)と「集計」を切り替える。
struct ReceiptsTab: View {
    @StateObject private var store = ReceiptStore()
    @State private var mode = 0   // 0: 一覧, 1: 集計
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if mode == 0 {
                ReceiptListView(showImporter: $showImporter)
            } else {
                ReceiptSummaryView()
            }
        }
        .environmentObject(store)
        // dropDestination(for: URL.self) だと Finder のファイル以外(写真.app・ブラウザ・
        // メール等の画像データ)を受け取れないため、NSItemProvider を直接受ける。
        .onDrop(of: [.fileURL, .image, .pdf], isTargeted: nil) { providers in
            store.importProviders(providers)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, .heic, .tiff, .webP, .image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.importFiles(urls)
            }
        }
        .alert("エラー", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .alert("取り込み結果", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var header: some View {
        HStack {
            Picker("", selection: $mode) {
                Text("一覧").tag(0)
                Text("集計").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            if store.importingCount > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("認識中 (\(store.importingCount))")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            Menu {
                Button("ファイルを選択…") { showImporter = true }
                Button("フォルダをまとめて取り込み…") { pickFolder() }
            } label: {
                Label("インポート", systemImage: "plus")
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // フォルダを選んで中のレシートを一括取り込みする(取り込み済みはスキップ)。
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "レシート(画像/PDF)が入ったフォルダを選んでください。サブフォルダも対象になります。"
        panel.prompt = "取り込む"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        store.importFolder(folder)
    }
}

// MARK: - レシート一覧

struct ReceiptListView: View {
    @EnvironmentObject var store: ReceiptStore
    @Binding var showImporter: Bool
    @State private var selection: UUID?
    @State private var yearFilter: Int?
    @State private var categoryFilter: ExpenseCategory?

    private var years: [Int] {
        Array(Set(store.receipts.map(\.year))).sorted(by: >)
    }

    private var filtered: [Receipt] {
        store.receipts
            .filter { yearFilter == nil || $0.year == yearFilter }
            .filter { categoryFilter == nil || $0.category == categoryFilter }
            .sorted { ($0.date ?? $0.importedAt) > ($1.date ?? $1.importedAt) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filterBar
                ScrollViewReader { proxy in
                    Group {
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            List(filtered, selection: $selection) { receipt in
                                ReceiptRow(receipt: receipt)
                                    .tag(receipt.id)
                                    .id(receipt.id)
                            }
                            .listStyle(.inset)
                        }
                    }
                    // 取り込み完了したレシートを自動選択してそこまでスクロールする。
                    // 日付順ソートで下の方に入ると見落とすため。フィルタで隠れる場合は解除する。
                    .onChange(of: store.lastImportedID) {
                        guard let id = store.lastImportedID,
                              let imported = store.receipts.first(where: { $0.id == id })
                        else { return }
                        if let y = yearFilter, y != imported.year { yearFilter = nil }
                        if let c = categoryFilter, c != imported.category { categoryFilter = nil }
                        selection = id
                        // フィルタ解除やリスト更新が反映された後の runloop でスクロールする。
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 300)

            Group {
                if let index = store.receipts.firstIndex(where: { $0.id == selection }) {
                    ReceiptDetail(receipt: $store.receipts[index])
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "receipt")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                        Text("レシートを選択、またはここに写真/PDF をドロップ")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 360)
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("年", selection: $yearFilter) {
                Text("すべての年").tag(Int?.none)
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(Int?.some(year))
                }
            }
            .frame(maxWidth: 150)

            Picker("カテゴリー", selection: $categoryFilter) {
                Text("すべて").tag(ExpenseCategory?.none)
                ForEach(ExpenseCategory.allCases) { cat in
                    Text(cat.jp).tag(ExpenseCategory?.some(cat))
                }
            }
            .frame(maxWidth: 240)

            Spacer()
            Text("\(filtered.count) 件")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("レシートの写真や PDF をここにドロップ")
                .font(.title3)
            Text("「インポート」ボタンからファイルを選ぶこともできます")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(receipt.status == .confirmed ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant.isEmpty ? "(店名なし)" : receipt.merchant)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let date = receipt.date {
                        Text(date, format: .dateTime.year().month().day())
                    } else {
                        Text("日付不明")
                    }
                    Text("·")
                    Text(receipt.category.jp)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(receipt.amount, format: .currency(code: "USD"))
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 詳細エディタ

struct ReceiptDetail: View {
    @EnvironmentObject var store: ReceiptStore
    @Binding var receipt: Receipt
    @State private var showDeleteConfirm = false
    @State private var showOCRText = false
    @State private var analyzingItems = false

    var body: some View {
        HSplitView {
            imagePane
                .frame(minWidth: 160)
            editorPane
                .frame(minWidth: 220)
        }
        .onChange(of: receipt) { store.save() }
    }

    private var imagePane: some View {
        Group {
            if let image = NSImage(contentsOf: receipt.fileURL) {
                // スクロールさせず、ペインの大きさに合わせて全体を表示する
                // (原寸表示だと iPhone 写真は巨大でスクロールしないと見えない)。
                VStack(spacing: 0) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                    Text("ダブルクリックで原寸表示")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .onTapGesture(count: 2) {
                    // プレビュー.app で開いて拡大確認できるようにする。
                    NSWorkspace.shared.open(receipt.fileURL)
                }
            } else {
                Text("画像が見つかりません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var editorPane: some View {
        Form {
            Section {
                TextField("店名", text: $receipt.merchant)
                DatePicker(
                    "日付",
                    selection: Binding(
                        get: { receipt.date ?? receipt.importedAt },
                        set: { receipt.date = $0 }
                    ),
                    displayedComponents: .date
                )
                if receipt.date == nil {
                    Text("⚠️ 日付を自動認識できませんでした。上で設定してください。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("金額", value: $receipt.amount, format: .currency(code: "USD"))
                Picker("カテゴリー", selection: $receipt.category) {
                    ForEach(ExpenseCategory.allCases) { cat in
                        Text(cat.jp).tag(cat)
                    }
                }
                TextField("メモ", text: $receipt.note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                HStack {
                    if receipt.status == .needsReview {
                        Button("内容を確認済みにする") {
                            receipt.status = .confirmed
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Label("確認済み", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
            }

            Section {
                DisclosureGroup("OCR テキスト", isExpanded: $showOCRText) {
                    ScrollView {
                        Text(receipt.ocrText.isEmpty ? "(なし)" : receipt.ocrText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                }
            }

            itemsSection

            Section {
                HStack {
                    Button("Finder で表示") {
                        NSWorkspace.shared.activateFileViewerSelecting([receipt.fileURL])
                    }
                    Spacer()
                    Button("削除", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "このレシートを削除しますか？",
            isPresented: $showDeleteConfirm
        ) {
            deleteDialogButtons
        } message: {
            Text("記録を削除し、元画像はゴミ箱に移動します。")
        }
    }

    // 購入商品の一覧。items が nil(未解析の旧データ)なら解析ボタンを出す。
    @ViewBuilder
    private var itemsSection: some View {
        Section("購入商品") {
            if let items = receipt.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.price, format: .currency(code: "USD"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                HStack {
                    Text("商品合計(税抜)").foregroundStyle(.secondary)
                    Spacer()
                    Text(items.reduce(0) { $0 + $1.price },
                         format: .currency(code: "USD"))
                        .monospacedDigit()
                }
                .font(.callout)
            } else {
                HStack {
                    Text(receipt.ocrText.isEmpty
                         ? "OCR テキストがないため解析できません"
                         : receipt.items == nil
                             ? "商品一覧は未解析です"
                             : "商品行を検出できませんでした")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    if analyzingItems {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(receipt.items == nil ? "商品を解析" : "再解析") {
                            analyzeItems()
                        }
                        .disabled(receipt.ocrText.isEmpty)
                    }
                }
            }
        }
    }

    // 保存済みの OCR テキストから商品一覧だけを解析し直す(店名・金額などの
    // 手直し済みフィールドは上書きしない)。
    private func analyzeItems() {
        analyzingItems = true
        let text = receipt.ocrText
        Task { @MainActor in
            let fields = await Extractor.extract(from: text)
            receipt.items = fields.items ?? []
            analyzingItems = false
        }
    }

    @ViewBuilder
    private var deleteDialogButtons: some View {
        Button("削除(元画像はゴミ箱へ)", role: .destructive) {
            store.delete(receipt)
        }
    }
}

// MARK: - 集計

struct ReceiptSummaryView: View {
    @EnvironmentObject var store: ReceiptStore
    @State private var year = Calendar.current.component(.year, from: Date())

    private var years: [Int] {
        let all = Set(store.receipts.map(\.year))
        return all.isEmpty ? [year] : Array(all).sorted(by: >)
    }

    private var yearReceipts: [Receipt] {
        store.receipts.filter { $0.year == year }
    }

    private struct CategorySummary: Identifiable {
        let category: ExpenseCategory
        let count: Int
        let total: Double
        var deductible: Double { total * category.deductibleRate }
        var id: String { category.rawValue }
    }

    private var summaries: [CategorySummary] {
        ExpenseCategory.allCases.compactMap { cat in
            let items = yearReceipts.filter { $0.category == cat }
            guard !items.isEmpty else { return nil }
            return CategorySummary(
                category: cat,
                count: items.count,
                total: items.reduce(0) { $0 + $1.amount })
        }
        .sorted { $0.total > $1.total }
    }

    private var needsReviewCount: Int {
        yearReceipts.filter { $0.status == .needsReview }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("対象年", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .frame(maxWidth: 160)

                if needsReviewCount > 0 {
                    Label("要確認 \(needsReviewCount) 件", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                Spacer()

                Button {
                    exportCSV()
                } label: {
                    Label("CSV エクスポート", systemImage: "square.and.arrow.up")
                }
                .disabled(yearReceipts.isEmpty)
            }
            .padding(12)

            if summaries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("\(String(year)) 年のレシートはまだありません")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(summaries) {
                    TableColumn("カテゴリー") { Text($0.category.jp) }
                    TableColumn("Schedule C") { Text($0.category.en).foregroundStyle(.secondary) }
                    TableColumn("件数") { s in
                        Text("\(s.count)").monospacedDigit()
                    }
                    .width(50)
                    TableColumn("合計") { s in
                        Text(s.total, format: .currency(code: "USD")).monospacedDigit()
                    }
                    .width(110)
                    TableColumn("控除見込") { s in
                        Text(s.deductible, format: .currency(code: "USD")).monospacedDigit()
                    }
                    .width(110)
                }

                totalsFooter
            }
        }
    }

    private var totalsFooter: some View {
        let total = summaries.reduce(0) { $0 + $1.total }
        let deductible = summaries.reduce(0) { $0 + $1.deductible }
        return HStack(spacing: 24) {
            Spacer()
            VStack(alignment: .trailing) {
                Text("支出合計").font(.caption).foregroundStyle(.secondary)
                Text(total, format: .currency(code: "USD"))
                    .font(.title3.bold()).monospacedDigit()
            }
            VStack(alignment: .trailing) {
                Text("控除見込合計").font(.caption).foregroundStyle(.secondary)
                Text(deductible, format: .currency(code: "USD"))
                    .font(.title3.bold()).monospacedDigit()
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "schedule-c-receipts-\(year).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Excel が UTF-8 を正しく認識するよう BOM を付ける。
        let bom = Data([0xEF, 0xBB, 0xBF])
        let data = bom + Data(store.csv(forYear: year).utf8)
        do {
            try data.write(to: url)
        } catch {
            store.lastError = "CSV 書き出し失敗: \(error.localizedDescription)"
        }
    }
}
