import Foundation

enum KiteAPIError: LocalizedError {
    case notAuthenticated
    case httpError(Int, String)
    case parseError(String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated. Please login."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .rateLimited: return "Rate limited. Try again shortly."
        }
    }
}

actor KiteAPIService {
    private let settings: AppSettings
    private let baseURL = "https://api.kite.trade"
    private var lastRequestTime = Date.distantPast
    private let minRequestInterval: TimeInterval = 0.35 // ~3 req/sec

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    // MARK: - Rate Limiting

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            let delay = minRequestInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestTime = Date()
    }

    // MARK: - Auth Header

    private var authHeader: String {
        get async {
            let apiKey = await MainActor.run { settings.kiteAPIKey }
            let token = await MainActor.run { settings.kiteAccessToken }
            return "token \(apiKey):\(token)"
        }
    }

    private func isAuthenticated() async -> Bool {
        await MainActor.run { settings.isTokenValid }
    }

    // MARK: - Fetch FnO Stock List

    func fetchFnOStockList() async throws -> [InstrumentInfo] {
        guard await isAuthenticated() else {
            print("[API] fetchFnOStockList: NOT authenticated")
            throw KiteAPIError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/instruments/NFO")!
        var request = URLRequest(url: url)
        request.setValue(await authHeader, forHTTPHeaderField: "Authorization")
        print("[API] fetchFnOStockList: fetching...")

        await throttle()
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        guard let csv = String(data: data, encoding: .utf8) else {
            throw KiteAPIError.parseError("Could not decode instruments CSV")
        }
        print("[API] NFO CSV: \(data.count) bytes, \(csv.components(separatedBy: "\n").count) lines")

        let result = parseNFOInstruments(csv: csv)
        print("[API] NFO parsed: \(result.count) FUT instruments")
        return result
    }

    /// Fetch NSE instrument tokens for given stock symbols
    func fetchNSEInstruments(symbols: Set<String>) async throws -> [String: InstrumentInfo] {
        guard await isAuthenticated() else {
            print("[API] fetchNSEInstruments: NOT authenticated")
            throw KiteAPIError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/instruments/NSE")!
        var request = URLRequest(url: url)
        request.setValue(await authHeader, forHTTPHeaderField: "Authorization")
        print("[API] fetchNSEInstruments: fetching for \(symbols.count) symbols...")

        await throttle()
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        guard let csv = String(data: data, encoding: .utf8) else {
            throw KiteAPIError.parseError("Could not decode NSE instruments CSV")
        }
        print("[API] NSE CSV: \(data.count) bytes, \(csv.components(separatedBy: "\n").count) lines")

        let result = parseNSEInstruments(csv: csv, filterSymbols: symbols)
        print("[API] NSE matched: \(result.count) out of \(symbols.count) symbols")
        return result
    }

    // MARK: - Fetch Quotes (batch)

    struct QuoteData {
        let lastPrice: Double
        let volume: Int
        let open: Double
        let high: Double
        let low: Double
        let close: Double
        let previousClose: Double
        let high52Week: Double
        let low52Week: Double
    }

    func fetchQuotes(symbols: [String]) async throws -> [String: QuoteData] {
        guard await isAuthenticated() else { throw KiteAPIError.notAuthenticated }

        var results: [String: QuoteData] = [:]

        // Kite allows up to 500 instruments per quote call
        let batches = symbols.chunked(into: 500)

        for batch in batches {
            let queryItems = batch.map { "i=NSE:\($0)" }.joined(separator: "&")
            let url = URL(string: "\(baseURL)/quote?\(queryItems)")!
            var request = URLRequest(url: url)
            request.setValue(await authHeader, forHTTPHeaderField: "Authorization")

            await throttle()
            let (data, response) = try await URLSession.shared.data(for: request)
            try checkResponse(response, data: data)

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dataDict = json?["data"] as? [String: Any] else {
                throw KiteAPIError.parseError("No data in quotes response")
            }

            for (key, value) in dataDict {
                guard let info = value as? [String: Any] else { continue }
                let symbol = key.replacingOccurrences(of: "NSE:", with: "")

                let ohlc = info["ohlc"] as? [String: Any] ?? [:]
                let depth52 = info["depth"] as? [String: Any]  // not needed for 52w

                let lastPrice = info["last_price"] as? Double ?? 0
                let volume = info["volume"] as? Int ?? 0
                let open = ohlc["open"] as? Double ?? 0
                let high = ohlc["high"] as? Double ?? 0
                let low = ohlc["low"] as? Double ?? 0
                let close = ohlc["close"] as? Double ?? 0
                let previousClose = info["last_price"] as? Double ?? 0 // close from ohlc is prev close in Kite

                // 52 week data from quote
                let high52 = info["ohlc"] as? [String: Any]  // Kite doesn't return 52W in quotes
                // We'll compute from historical data instead

                results[symbol] = QuoteData(
                    lastPrice: lastPrice,
                    volume: volume,
                    open: open,
                    high: high,
                    low: low,
                    close: close,
                    previousClose: close, // ohlc.close = previous day's close in Kite
                    high52Week: 0,  // computed from historical
                    low52Week: 0    // computed from historical
                )
            }
        }

        return results
    }

    // MARK: - Fetch Historical Data

    func fetchHistoricalData(instrumentToken: Int, from: Date, to: Date, interval: String = "day") async throws -> [Candle] {
        guard await isAuthenticated() else { throw KiteAPIError.notAuthenticated }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let fromStr = df.string(from: from)
        let toStr = df.string(from: to)

        let url = URL(string: "\(baseURL)/instruments/historical/\(instrumentToken)/\(interval)?from=\(fromStr)&to=\(toStr)")!
        var request = URLRequest(url: url)
        request.setValue(await authHeader, forHTTPHeaderField: "Authorization")

        await throttle()
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
            throw KiteAPIError.rateLimited
        }
        try checkResponse(response, data: data)

        return try parseHistoricalData(data: data)
    }

    // MARK: - Parsing

    private func parseNFOInstruments(csv: String) -> [InstrumentInfo] {
        let lines = csv.components(separatedBy: "\n")
        guard lines.count > 1 else {
            print("[PARSE] NFO: no lines!")
            return []
        }

        // Find column indices from header
        let header = lines[0].components(separatedBy: ",")
        print("[PARSE] NFO header cols: \(header)")
        guard let tokenIdx = header.firstIndex(of: "instrument_token"),
              let symbolIdx = header.firstIndex(of: "tradingsymbol"),
              let nameIdx = header.firstIndex(of: "name"),
              let exchangeIdx = header.firstIndex(of: "exchange"),
              let typeIdx = header.firstIndex(of: "instrument_type") else {
            print("[PARSE] NFO: header column lookup FAILED")
            print("[PARSE] NFO: token=\(header.firstIndex(of: "instrument_token") as Any), symbol=\(header.firstIndex(of: "tradingsymbol") as Any), name=\(header.firstIndex(of: "name") as Any), exchange=\(header.firstIndex(of: "exchange") as Any), type=\(header.firstIndex(of: "instrument_type") as Any)")
            return []
        }

        var seenNames = Set<String>()
        var instruments: [InstrumentInfo] = []

        for line in lines.dropFirst() where !line.isEmpty {
            let cols = parseCSVLine(line)
            guard cols.count > max(tokenIdx, symbolIdx, nameIdx, exchangeIdx, typeIdx) else { continue }

            // Only FUT instruments to get unique underlying names
            let instType = cols[typeIdx]
            guard instType == "FUT" else { continue }

            let name = cols[nameIdx]
            guard !name.isEmpty, !seenNames.contains(name) else { continue }
            seenNames.insert(name)

            let token = Int(cols[tokenIdx]) ?? 0
            instruments.append(InstrumentInfo(
                id: token,
                tradingsymbol: cols[symbolIdx],
                name: name,
                exchange: "NFO",
                instrumentToken: token
            ))
        }

        return instruments
    }

    private func parseNSEInstruments(csv: String, filterSymbols: Set<String>) -> [String: InstrumentInfo] {
        let lines = csv.components(separatedBy: "\n")
        guard lines.count > 1 else { return [:] }

        let header = lines[0].components(separatedBy: ",")
        guard let tokenIdx = header.firstIndex(of: "instrument_token"),
              let symbolIdx = header.firstIndex(of: "tradingsymbol"),
              let nameIdx = header.firstIndex(of: "name"),
              let exchangeIdx = header.firstIndex(of: "exchange"),
              let typeIdx = header.firstIndex(of: "instrument_type") else {
            return [:]
        }

        var result: [String: InstrumentInfo] = [:]

        for line in lines.dropFirst() where !line.isEmpty {
            let cols = parseCSVLine(line)
            guard cols.count > max(tokenIdx, symbolIdx, nameIdx, exchangeIdx, typeIdx) else { continue }

            let instType = cols[typeIdx]
            guard instType == "EQ" else { continue }

            let symbol = cols[symbolIdx]
            guard filterSymbols.contains(symbol) else { continue }

            let token = Int(cols[tokenIdx]) ?? 0
            result[symbol] = InstrumentInfo(
                id: token,
                tradingsymbol: symbol,
                name: cols[nameIdx],
                exchange: cols[exchangeIdx],
                instrumentToken: token
            )
        }

        return result
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    private func parseHistoricalData(data: Data) throws -> [Candle] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataDict = json?["data"] as? [String: Any],
              let candles = dataDict["candles"] as? [[Any]] else {
            throw KiteAPIError.parseError("Invalid historical data format")
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

        return candles.compactMap { arr -> Candle? in
            guard arr.count >= 6,
                  let dateStr = arr[0] as? String,
                  let date = df.date(from: dateStr),
                  let open = arr[1] as? Double,
                  let high = arr[2] as? Double,
                  let low = arr[3] as? Double,
                  let close = arr[4] as? Double,
                  let volume = arr[5] as? Int else { return nil }
            return Candle(date: date, open: open, high: high, low: low, close: close, volume: volume)
        }
    }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            if http.statusCode == 429 {
                throw KiteAPIError.rateLimited
            }
            throw KiteAPIError.httpError(http.statusCode, body)
        }
    }
}

// MARK: - Array chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
