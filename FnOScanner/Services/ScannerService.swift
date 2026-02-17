import Foundation

@MainActor
class ScannerService: ObservableObject {
    @Published var progress: ScanProgress = .idle
    @Published var statusMessage: String = ""

    private let api: KiteAPIService
    private let engine: AnalysisEngine
    private let settings: AppSettings

    // Cache
    private var cachedFnOSymbols: [String] = []
    private var cachedNSEInstruments: [String: InstrumentInfo] = [:]
    private var cachedHistorical: [String: (candles: [Candle], fetchDate: Date)] = [:]
    private var cacheDate: Date?

    enum ScanProgress: Equatable {
        case idle
        case fetchingInstruments
        case fetchingQuotes
        case fetchingHistorical(current: Int, total: Int)
        case analyzing
        case done
        case error(String)

        static func == (lhs: ScanProgress, rhs: ScanProgress) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.fetchingInstruments, .fetchingInstruments),
                 (.fetchingQuotes, .fetchingQuotes), (.analyzing, .analyzing),
                 (.done, .done):
                return true
            case (.fetchingHistorical(let a, let b), .fetchingHistorical(let c, let d)):
                return a == c && b == d
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.api = KiteAPIService(settings: settings)
        self.engine = AnalysisEngine(settings: settings)
    }

    func scan() async -> [ScanResult] {
        do {
            // Step 1: Fetch FnO instrument list
            progress = .fetchingInstruments
            statusMessage = "Fetching FnO stock list..."

            let needRefreshInstruments = !Calendar.current.isDateInToday(cacheDate ?? .distantPast)

            if needRefreshInstruments || cachedFnOSymbols.isEmpty {
                let nfoInstruments = try await api.fetchFnOStockList()
                let symbols = Array(Set(nfoInstruments.map(\.name))).sorted()
                cachedFnOSymbols = symbols
                print("📊 NFO FUT stocks found: \(symbols.count)")

                // Step 2: Map to NSE instrument tokens
                let nseInstruments = try await api.fetchNSEInstruments(symbols: Set(symbols))
                cachedNSEInstruments = nseInstruments
                cacheDate = Date()
                print("📊 NSE EQ instruments matched: \(nseInstruments.count) out of \(symbols.count)")

                // Log any symbols that didn't match
                let unmatched = symbols.filter { nseInstruments[$0] == nil }
                if !unmatched.isEmpty {
                    print("⚠️ Unmatched symbols (\(unmatched.count)): \(unmatched.prefix(10).joined(separator: ", "))\(unmatched.count > 10 ? "..." : "")")
                }
            }

            let symbols = cachedFnOSymbols.filter { cachedNSEInstruments[$0] != nil }
            statusMessage = "Found \(symbols.count) FnO stocks"

            // Step 3: Fetch quotes in batch
            progress = .fetchingQuotes
            statusMessage = "Fetching live quotes for \(symbols.count) stocks..."
            let quotes = try await api.fetchQuotes(symbols: symbols)

            // Step 4: Fetch historical data (throttled)
            let total = symbols.count
            var stocks: [Stock] = []

            let fromDate = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
            let toDate = Date()

            var failedCount = 0
            for (idx, symbol) in symbols.enumerated() {
                progress = .fetchingHistorical(current: idx + 1, total: total)
                statusMessage = "Fetching history: \(symbol) (\(idx + 1)/\(total))"

                guard let instrument = cachedNSEInstruments[symbol] else { continue }
                let quote = quotes[symbol]

                // Check cache
                var candles: [Candle]
                if let cached = cachedHistorical[symbol],
                   Calendar.current.isDateInToday(cached.fetchDate) {
                    candles = cached.candles
                } else {
                    do {
                        candles = try await api.fetchHistoricalData(
                            instrumentToken: instrument.instrumentToken,
                            from: fromDate,
                            to: toDate
                        )
                        cachedHistorical[symbol] = (candles, Date())
                    } catch KiteAPIError.rateLimited {
                        // Wait and retry once
                        statusMessage = "Rate limited, waiting 2s... (\(symbol))"
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        do {
                            candles = try await api.fetchHistoricalData(
                                instrumentToken: instrument.instrumentToken,
                                from: fromDate,
                                to: toDate
                            )
                            cachedHistorical[symbol] = (candles, Date())
                        } catch {
                            print("⚠️ Failed to fetch \(symbol) after retry: \(error)")
                            failedCount += 1
                            continue
                        }
                    } catch {
                        print("⚠️ Failed to fetch \(symbol): \(error)")
                        failedCount += 1
                        continue
                    }
                }

                let stock = Stock(
                    id: symbol,
                    instrumentToken: instrument.instrumentToken,
                    name: instrument.name,
                    exchange: "NSE",
                    dailyCandles: candles,
                    currentPrice: quote?.lastPrice ?? 0,
                    currentVolume: quote?.volume ?? 0,
                    dayOpen: quote?.open,
                    dayHigh: quote?.high,
                    dayLow: quote?.low,
                    dayClose: quote?.close,
                    previousClose: quote?.previousClose
                )
                stocks.append(stock)
            }

            // Step 5: Run analysis
            progress = .analyzing
            statusMessage = "Analyzing \(stocks.count) stocks..."

            let results = stocks.map { engine.analyze(stock: $0) }
                .sorted { $0.score > $1.score }

            progress = .done
            let flagged = results.filter { $0.score > 0 }.count
            let failMsg = failedCount > 0 ? " (\(failedCount) failed)" : ""
            statusMessage = "Scan complete. \(flagged) flagged out of \(stocks.count) stocks.\(failMsg)"

            return results

        } catch {
            progress = .error(error.localizedDescription)
            statusMessage = "Error: \(error.localizedDescription)"
            return []
        }
    }

    func clearCache() {
        cachedFnOSymbols = []
        cachedNSEInstruments = [:]
        cachedHistorical = [:]
        cacheDate = nil
    }
}
