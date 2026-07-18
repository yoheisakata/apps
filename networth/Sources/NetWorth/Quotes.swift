import Foundation

// Yahoo Finance の公開 chart API から現在株価を取得する(API キー不要)。
// SimpleFIN の時価はおおむね1日1回の同期値なので、保有銘柄の表示時に
// 株数 × 現在株価 で時価を補正するために使う。
enum QuoteService {
    struct Quote {
        var price: Double
        var time: Date  // 取引所での最終約定時刻
    }

    struct PricePoint: Identifiable {
        var id: Date { date }
        var date: Date
        var close: Double
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable { var result: [Item]? }
        struct Item: Decodable {
            var meta: Meta
            var timestamp: [Double]?
            var indicators: Indicators?
        }
        struct Meta: Decodable {
            var regularMarketPrice: Double?
            var regularMarketTime: Double?
        }
        struct Indicators: Decodable {
            var quote: [QuoteData]?
        }
        struct QuoteData: Decodable {
            var close: [Double?]?
        }
        var chart: Chart
    }

    private static func chartRequest(symbol: String, interval: String, range: String) -> URLRequest? {
        guard let encoded = symbol.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed),
              let url = URL(string:
                "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=\(interval)&range=\(range)")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        return req
    }

    static func fetch(symbol: String) async -> Quote? {
        guard let req = chartRequest(symbol: symbol, interval: "1d", range: "1d")
        else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let meta = decoded.chart.result?.first?.meta,
              let price = meta.regularMarketPrice
        else { return nil }
        let time = meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) } ?? Date()
        return Quote(price: price, time: time)
    }

    static func fetchHistory(symbol: String, range: String = "3mo") async -> [PricePoint] {
        guard let req = chartRequest(symbol: symbol, interval: "1d", range: range)
        else { return [] }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let item = decoded.chart.result?.first,
              let timestamps = item.timestamp,
              let closes = item.indicators?.quote?.first?.close
        else { return [] }
        var points: [PricePoint] = []
        for (i, ts) in timestamps.enumerated() {
            guard i < closes.count, let close = closes[i] else { continue }
            points.append(PricePoint(date: Date(timeIntervalSince1970: ts), close: close))
        }
        return points
    }

    static func fetchAllHistory(symbols: [String], range: String = "3mo") async -> [String: [PricePoint]] {
        await withTaskGroup(of: (String, [PricePoint]).self) { group in
            for s in symbols {
                group.addTask { (s, await fetchHistory(symbol: s, range: range)) }
            }
            var out: [String: [PricePoint]] = [:]
            for await (s, pts) in group {
                if !pts.isEmpty { out[s] = pts }
            }
            return out
        }
    }

    /// 複数銘柄を並列で取得する。取れなかった銘柄は結果に含めない(表示側でフォールバック)。
    static func fetchAll(symbols: [String]) async -> [String: Quote] {
        await withTaskGroup(of: (String, Quote?).self) { group in
            for s in symbols {
                group.addTask { (s, await fetch(symbol: s)) }
            }
            var out: [String: Quote] = [:]
            for await (s, q) in group {
                if let q { out[s] = q }
            }
            return out
        }
    }
}
