import Foundation
import AppKit
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
@preconcurrency import Vision

// レシート管理(Schedule C 経費整理)のデータ層。
// 元は receipts-mac/ の単体アプリだったものを NetWorth のタブとして統合した。
// データは従来どおり ~/Library/Application Support/Receipts/ に保存する。

// Schedule C(個人事業主)の経費カテゴリー。
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case advertising
    case carTruck
    case commissions
    case insurance
    case legal
    case office
    case supplies
    case repairs
    case rent
    case travel
    case meals
    case utilities
    case software
    case education
    case equipment
    case other
    case personal

    var id: String { rawValue }

    var jp: String {
        switch self {
        case .advertising: return "広告宣伝費"
        case .carTruck:    return "車両・ガソリン"
        case .commissions: return "外注・手数料"
        case .insurance:   return "保険料"
        case .legal:       return "法務・会計・専門サービス"
        case .office:      return "事務用品・オフィス経費"
        case .supplies:    return "消耗品・材料"
        case .repairs:     return "修繕・メンテナンス"
        case .rent:        return "賃借料・リース"
        case .travel:      return "旅費・交通費"
        case .meals:       return "飲食費(50%控除)"
        case .utilities:   return "通信費・水道光熱費"
        case .software:    return "ソフトウェア・サブスク"
        case .education:   return "教育・研修"
        case .equipment:   return "機材・備品"
        case .other:       return "その他経費"
        case .personal:    return "対象外(私用)"
        }
    }

    var en: String {
        switch self {
        case .advertising: return "Advertising"
        case .carTruck:    return "Car and Truck Expenses"
        case .commissions: return "Commissions and Fees"
        case .insurance:   return "Insurance"
        case .legal:       return "Legal and Professional Services"
        case .office:      return "Office Expense"
        case .supplies:    return "Supplies"
        case .repairs:     return "Repairs and Maintenance"
        case .rent:        return "Rent or Lease"
        case .travel:      return "Travel"
        case .meals:       return "Meals"
        case .utilities:   return "Utilities"
        case .software:    return "Software / Subscriptions"
        case .education:   return "Education / Training"
        case .equipment:   return "Equipment"
        case .other:       return "Other Expenses"
        case .personal:    return "Personal (Not Deductible)"
        }
    }

    // 控除見込みの掛け率。meals は 50%、私用は 0。
    var deductibleRate: Double {
        switch self {
        case .meals:    return 0.5
        case .personal: return 0
        default:        return 1
        }
    }
}

enum ReceiptStatus: String, Codable {
    case needsReview  // 自動抽出のまま(要確認)
    case confirmed    // 内容を確認済み
}

// レシートの商品行(品名と価格)。
struct ReceiptItem: Codable, Equatable, Hashable {
    var name = ""
    var price = 0.0
}

struct Receipt: Identifiable, Codable, Equatable {
    var id = UUID()
    var importedAt = Date()
    var date: Date?
    var merchant = ""
    var amount = 0.0
    var category = ExpenseCategory.other
    var note = ""
    var fileName = ""   // originals/ 内の相対パス
    var fileHash: String?   // 元ファイルの SHA-256(重複取り込みの検出用)
    var ocrText = ""
    // 商品一覧。nil = 未解析(旧データ)、[] = 解析したが商品行を検出できず。
    // Optional なのは旧データ(キーなし)を decode できるようにするため。
    var items: [ReceiptItem]?
    var status = ReceiptStatus.needsReview

    var year: Int {
        Calendar.current.component(.year, from: date ?? importedAt)
    }

    var fileURL: URL {
        ReceiptStore.originalsDir.appendingPathComponent(fileName)
    }
}

@MainActor
final class ReceiptStore: ObservableObject {
    @Published var receipts: [Receipt] = []
    @Published var importingCount = 0   // 認識処理中の枚数
    @Published var lastError: String?
    @Published var notice: String?         // エラーではないお知らせ(取り込み結果など)
    @Published var lastImportedID: UUID?   // 直近に取り込んだレシート(一覧で自動選択する)

    // 取り込み済みファイルの SHA-256。取り込み開始時に予約として追加するので、
    // 同じファイルを同時に複数回ドロップしても二重登録されない。
    private var knownHashes: Set<String> = []
    private var hashesReady = false

    nonisolated static let baseDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Receipts")
    nonisolated static let originalsDir = baseDir.appendingPathComponent("originals")
    private var dataURL: URL { Self.baseDir.appendingPathComponent("receipts.json") }

    init() {
        try? FileManager.default.createDirectory(at: Self.originalsDir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: dataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([Receipt].self, from: data) {
            receipts = loaded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(receipts) {
            try? data.write(to: dataURL, options: .atomic)
        }
    }

    // MARK: - インポート

    nonisolated static let allowedExtensions = ["pdf", "png", "jpg", "jpeg", "heic", "heif",
                                                "tiff", "tif", "webp", "gif", "bmp"]

    func importFiles(_ urls: [URL]) {
        var skipped: [String] = []
        for url in urls {
            if Self.allowedExtensions.contains(url.pathExtension.lowercased()) {
                Task {
                    if await importOne(url) == .duplicate {
                        notice = "取り込み済みのためスキップ: \(url.lastPathComponent)"
                    }
                }
            } else {
                skipped.append(url.lastPathComponent)
            }
        }
        // 黙って無視すると「取り込んだのに表示されない」ように見えるため必ず通知する。
        if !skipped.isEmpty {
            lastError = "未対応の形式のためスキップ: \(skipped.joined(separator: ", "))"
        }
    }

    // フォルダ内のレシートを(サブフォルダ含めて)まとめて取り込む。
    // 既に取り込み済みのファイル(内容が同一)はスキップする。
    func importFolder(_ folder: URL) {
        let files = Self.receiptFiles(in: folder)
        Task {
            guard !files.isEmpty else {
                notice = "「\(folder.lastPathComponent)」に取り込めるファイル(画像/PDF)が見つかりませんでした。"
                return
            }

            var imported = 0, duplicates = 0, failed = 0
            for file in files {
                switch await importOne(file) {
                case .imported:  imported += 1
                case .duplicate: duplicates += 1
                case .failed:    failed += 1
                }
            }
            var parts = ["\(imported) 件を取り込みました"]
            if duplicates > 0 { parts.append("\(duplicates) 件は取り込み済みのためスキップ") }
            if failed > 0 { parts.append("\(failed) 件は失敗") }
            notice = "フォルダ取り込み完了: " + parts.joined(separator: "、")
        }
    }

    // フォルダ内(サブフォルダ含む)の取り込み対象ファイルをファイル名順で返す。
    private nonisolated static func receiptFiles(in folder: URL) -> [URL] {
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator
            where allowedExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - 重複検出

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // 旧データにはハッシュがないので、初回に元画像から計算して埋める。
    private func ensureHashes() {
        guard !hashesReady else { return }
        hashesReady = true
        var changed = false
        for i in receipts.indices where receipts[i].fileHash == nil {
            if let data = try? Data(contentsOf: receipts[i].fileURL) {
                receipts[i].fileHash = Self.sha256(data)
                changed = true
            }
        }
        knownHashes = Set(receipts.compactMap(\.fileHash))
        if changed { save() }
    }

    // Finder 以外(写真.app・ブラウザ・メールなど)からのドラッグはファイル URL ではなく
    // 画像/PDF データとして届くことがあるので、NSItemProvider を直接受けて取り込む。
    func importProviders(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in self.importFiles([url]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                handled = true
                loadData(from: provider, typeIdentifier: UTType.pdf.identifier, ext: "pdf")
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                // 登録された型から image に適合する具象型(png/jpeg/heic 等)を選ぶ。
                let typeId = provider.registeredTypeIdentifiers.first {
                    UTType($0)?.conforms(to: .image) == true
                } ?? UTType.png.identifier
                let ext = UTType(typeId)?.preferredFilenameExtension ?? "png"
                loadData(from: provider, typeIdentifier: typeId, ext: ext)
            }
        }
        if !handled {
            lastError = "ドロップされた項目を読み込めませんでした。いったんファイルとして保存してからドロップしてください。"
        }
        return handled
    }

    private func loadData(from provider: NSItemProvider, typeIdentifier: String, ext: String) {
        let suggested = provider.suggestedName
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            Task { @MainActor in
                guard let data else {
                    self.lastError = "ドロップの読み込み失敗: \(error?.localizedDescription ?? "不明なエラー")"
                    return
                }
                self.importData(data, ext: ext, suggestedName: suggested)
            }
        }
    }

    // データ(ファイルではない)で届いたレシートを一時ファイルに書き出して取り込む。
    private func importData(_ data: Data, ext: String, suggestedName: String?) {
        var base = suggestedName ?? "dropped"
        if (base as NSString).pathExtension.lowercased() == ext.lowercased() {
            base = (base as NSString).deletingPathExtension
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6)).\(ext)")
        do {
            try data.write(to: tmp)
        } catch {
            lastError = "一時ファイル作成失敗: \(error.localizedDescription)"
            return
        }
        Task { await importOne(tmp) }
    }

    enum ImportResult { case imported, duplicate, failed }

    @discardableResult
    private func importOne(_ source: URL) async -> ImportResult {
        importingCount += 1
        defer { importingCount -= 1 }

        // 重複チェック(内容の SHA-256 が既存レコードと一致したらスキップ)。
        ensureHashes()
        guard let data = try? Data(contentsOf: source) else {
            lastError = "読み込み失敗: \(source.lastPathComponent)"
            return .failed
        }
        let hash = Self.sha256(data)
        if knownHashes.contains(hash) { return .duplicate }
        knownHashes.insert(hash)

        // 元画像を年フォルダにコピーして保全する(監査対応のため加工しない)。
        let year = Calendar.current.component(.year, from: Date())
        let relDir = "\(year)"
        let dir = Self.originalsDir.appendingPathComponent(relDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.prefix(8))-\(source.lastPathComponent)"
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            lastError = "コピー失敗: \(source.lastPathComponent) — \(error.localizedDescription)"
            knownHashes.remove(hash)
            return .failed
        }

        var receipt = Receipt()
        receipt.fileName = "\(relDir)/\(name)"
        receipt.fileHash = hash

        do {
            let text = try await OCR.extractText(from: dest)
            receipt.ocrText = text
            let fields = await Extractor.extract(from: text)
            receipt.merchant = fields.merchant
            receipt.date = fields.date
            receipt.amount = fields.total
            receipt.category = fields.category
            receipt.items = fields.items
        } catch {
            lastError = "認識失敗: \(source.lastPathComponent) — \(error.localizedDescription)"
            receipt.merchant = source.deletingPathExtension().lastPathComponent
        }

        receipts.insert(receipt, at: 0)
        lastImportedID = receipt.id
        save()
        return .imported
    }

    // MARK: - 削除(元画像はゴミ箱へ)

    func delete(_ receipt: Receipt) {
        try? FileManager.default.trashItem(at: receipt.fileURL, resultingItemURL: nil)
        receipts.removeAll { $0.id == receipt.id }
        // ハッシュも忘れて、削除後の再取り込みをスキップさせない。
        if let hash = receipt.fileHash { knownHashes.remove(hash) }
        save()
    }

    // MARK: - CSV エクスポート

    func csv(forYear year: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var lines = ["date,merchant,amount,category,category_en,deductible_amount,note,file,status"]
        let target = receipts
            .filter { $0.year == year }
            .sorted { ($0.date ?? $0.importedAt) < ($1.date ?? $1.importedAt) }
        for r in target {
            let date = r.date.map { formatter.string(from: $0) } ?? ""
            let deductible = r.amount * r.category.deductibleRate
            let cols = [
                date,
                r.merchant,
                String(format: "%.2f", r.amount),
                r.category.jp,
                r.category.en,
                String(format: "%.2f", deductible),
                r.note,
                r.fileName,
                r.status == .confirmed ? "confirmed" : "needs_review",
            ]
            lines.append(cols.map(Self.csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

enum OCRError: LocalizedError {
    case unreadable
    var errorDescription: String? { "画像を読み込めませんでした" }
}

enum OCR {
    // 画像 or PDF からテキストを取り出す。PDF にテキストレイヤーがあればそれを使い、
    // なければページを高解像度でレンダリングして OCR する。
    static func extractText(from url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            if let embedded = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               embedded.count >= 30 {
                return embedded
            }
            var pages: [String] = []
            for i in 0..<min(doc.pageCount, 4) {
                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let scale: CGFloat = 3
                let image = page.thumbnail(
                    of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
                    for: .mediaBox)
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    pages.append(try await recognize(cg))
                }
            }
            return pages.joined(separator: "\n")
        }

        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.unreadable
        }
        return try await recognize(cg)
    }

    static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "ja-JP"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

#if canImport(FoundationModels)
import FoundationModels
#endif

struct ExtractedFields {
    var merchant = ""
    var date: Date?
    var total = 0.0
    var category = ExpenseCategory.other
    // nil = 商品解析なし(AI が使えなかった)。[] = 解析したが商品行なし。
    var items: [ReceiptItem]?
}

enum Extractor {
    // まずヒューリスティックで抽出し、Apple Intelligence(オンデバイス LLM)が
    // 使えれば FoundationModels の結果で上書きする。
    static func extract(from text: String) async -> ExtractedFields {
        var fields = heuristics(text)

        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability,
           let ai = try? await aiExtract(text) {
            if !ai.merchant.trimmingCharacters(in: .whitespaces).isEmpty {
                fields.merchant = ai.merchant.trimmingCharacters(in: .whitespaces)
            }
            if let d = parseISODate(ai.date) { fields.date = d }
            if ai.total > 0 { fields.total = ai.total }
            if let c = ExpenseCategory(rawValue: ai.category) { fields.category = c }
            fields.items = ai.items
                .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ReceiptItem(name: $0.name.trimmingCharacters(in: .whitespaces),
                                   price: $0.price) }
        }
        #endif

        return fields
    }

    // MARK: - FoundationModels(macOS 26 / Apple Intelligence)

    // 注意: オンデバイスモデルは Apple Intelligence の言語設定(このMacでは英語)以外の
    // プロンプトを unsupportedLanguageOrLocale で拒否するため、プロンプトは英語で書く。
    #if canImport(FoundationModels)
    @Generable
    struct AIReceiptFields {
        @Guide(description: "Merchant or payee name, e.g. Home Depot")
        var merchant: String
        @Guide(description: "Receipt date in YYYY-MM-DD format, or empty string if unknown")
        var date: String
        @Guide(description: "Final total amount paid including tax and tip, number only")
        var total: Double
        @Guide(description: """
            Schedule C expense category for a sole proprietor. Exactly one of: \
            advertising, carTruck (car/gas), commissions (contractors/fees), insurance, \
            legal (legal/accounting), office (office expense), supplies (materials), \
            repairs, rent, travel, meals, utilities (phone/internet/power), \
            software (software/subscriptions), education, equipment, other, \
            personal (not business related)
            """)
        var category: String
        @Guide(description: """
            Purchased line items (product/service name and its price) in the order \
            printed. When item names and prices are split into separate line groups \
            by OCR, match them by order. Empty array if the receipt has no itemized lines.
            """)
        var items: [AIItem]
    }

    @Generable
    struct AIItem {
        @Guide(description: "Item name as printed on the receipt")
        var name: String
        @Guide(description: "Item price (before tax). 0 if unreadable")
        var price: Double
    }

    static func aiExtract(_ text: String) async throws -> AIReceiptFields {
        let session = LanguageModelSession(instructions: """
            You extract expense data from OCR text of receipts for a sole proprietor's \
            US tax return (Schedule C). OCR may contain errors and columns may be split \
            across lines; return the most plausible values.
            """)
        let prompt = "Extract the fields from this receipt OCR text:\n\n"
            + String(text.prefix(3000))
        let response = try await session.respond(to: prompt, generating: AIReceiptFields.self)
        return response.content
    }
    #endif

    // MARK: - ヒューリスティック(フォールバック)

    static func heuristics(_ text: String) -> ExtractedFields {
        var fields = ExtractedFields()
        let lines = text.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        // 店名: 最初の「文字を含む」行。
        if let first = lines.first(where: { line in
            line.count >= 3 && line.rangeOfCharacter(from: .letters) != nil
        }) {
            fields.merchant = String(first.prefix(40))
        }

        // 日付: NSDataDetector で最初に見つかった日付。
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            let now = Date()
            let candidates = detector.matches(in: text, range: range).compactMap(\.date)
            // 未来すぎる/古すぎる日付は誤検出とみなす。
            fields.date = candidates.first {
                $0 <= now.addingTimeInterval(86400) &&
                $0 > now.addingTimeInterval(-5 * 365 * 86400)
            }
        }

        // 合計金額: total 系キーワードを含む行の金額を優先、なければ全体の最大値。
        let amountPattern = try! NSRegularExpression(
            pattern: #"(\d{1,3}(?:,\d{3})*\.\d{2})"#)
        func amounts(in line: String) -> [Double] {
            let range = NSRange(line.startIndex..., in: line)
            return amountPattern.matches(in: line, range: range).compactMap {
                guard let r = Range($0.range(at: 1), in: line) else { return nil }
                return Double(line[r].replacingOccurrences(of: ",", with: ""))
            }
        }
        let keywords = ["total", "amount due", "balance due", "grand total", "合計", "総額"]
        let exclusions = ["subtotal", "sub total", "小計"]
        let keywordAmounts = lines.filter { line in
            let lower = line.lowercased()
            return keywords.contains(where: lower.contains)
                && !exclusions.contains(where: lower.contains)
        }.flatMap(amounts)
        if let total = keywordAmounts.max() {
            fields.total = total
        } else if let maxAmount = lines.flatMap(amounts).max() {
            fields.total = maxAmount
        }

        return fields
    }

    static func parseISODate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }
}
