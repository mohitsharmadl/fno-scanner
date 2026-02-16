import Foundation
import Combine

@MainActor
class ScannerViewModel: ObservableObject {
    @Published var scanResults: [ScanResult] = []
    @Published var filteredResults: [ScanResult] = []
    @Published var selectedStock: ScanResult?
    @Published var isScanning = false
    @Published var lastScanTime: Date?
    @Published var activeFilter: ScanFilter = .all
    @Published var searchText: String = ""
    @Published var sortOrder: SortOrder = .score

    let settings = AppSettings.shared
    let authService = KiteAuthService()
    let scannerService: ScannerService

    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    enum ScanFilter: String, CaseIterable {
        case all = "All"
        case confluencePullback = "Confluence Pullback"
        case volumeSpikes = "Volume Spikes"
        case nearEMA = "Near EMA"
        case breakouts = "Breakouts"
        case flagged = "Flagged (Score > 0)"
    }

    enum SortOrder: String, CaseIterable {
        case score = "Score"
        case symbol = "Symbol"
        case price = "Price"
        case volumeMultiplier = "Volume"
        case priceChange = "Change %"
    }

    init() {
        self.scannerService = ScannerService(settings: settings)
        setupBindings()
    }

    private func setupBindings() {
        // Re-filter when filter/search/sort changes
        Publishers.CombineLatest3($activeFilter, $searchText, $sortOrder)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] filter, search, sort in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true

        Task {
            let results = await scannerService.scan()
            self.scanResults = results
            self.applyFilters()
            self.lastScanTime = Date()
            self.isScanning = false
        }
    }

    func applyFilters() {
        var results = scanResults

        // Apply filter
        switch activeFilter {
        case .all:
            break
        case .confluencePullback:
            results = results.filter(\.confluence.detected)
        case .volumeSpikes:
            results = results.filter(\.volumeSpike)
        case .nearEMA:
            results = results.filter { $0.nearEMACount > 0 }
        case .breakouts:
            results = results.filter(\.breakout52Week)
        case .flagged:
            results = results.filter { $0.score > 0 }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.stock.id.lowercased().contains(query) ||
                $0.stock.name.lowercased().contains(query)
            }
        }

        // Apply sort
        switch sortOrder {
        case .score:
            results.sort { $0.score > $1.score }
        case .symbol:
            results.sort { $0.stock.id < $1.stock.id }
        case .price:
            results.sort { $0.stock.currentPrice > $1.stock.currentPrice }
        case .volumeMultiplier:
            results.sort { $0.volumeMultiplier > $1.volumeMultiplier }
        case .priceChange:
            results.sort { $0.priceChange > $1.priceChange }
        }

        filteredResults = results
    }

    func setupAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(settings.autoRefreshMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.isMarketOpen == true else { return }
                self?.startScan()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    var isMarketOpen: Bool {
        let calendar = Calendar.current
        let now = Date()

        // Convert to IST
        var istCalendar = Calendar(identifier: .gregorian)
        istCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        let weekday = istCalendar.component(.weekday, from: now)
        guard (2...6).contains(weekday) else { return false } // Mon-Fri

        let hour = istCalendar.component(.hour, from: now)
        let minute = istCalendar.component(.minute, from: now)
        let totalMinutes = hour * 60 + minute

        let marketOpen = 9 * 60 + 15   // 9:15 AM
        let marketClose = 15 * 60 + 30 // 3:30 PM

        return totalMinutes >= marketOpen && totalMinutes <= marketClose
    }

    var scanProgressText: String {
        scannerService.statusMessage
    }

    var scanProgress: ScannerService.ScanProgress {
        scannerService.progress
    }

    var progressPercent: Double {
        switch scannerService.progress {
        case .fetchingHistorical(let current, let total):
            return Double(current) / Double(total)
        case .done:
            return 1.0
        default:
            return 0
        }
    }

    // Stats
    var totalStocks: Int { scanResults.count }
    var confluenceCount: Int { scanResults.filter(\.confluence.detected).count }
    var volumeSpikeCount: Int { scanResults.filter(\.volumeSpike).count }
    var nearEMACount: Int { scanResults.filter { $0.nearEMACount > 0 }.count }
    var breakoutCount: Int { scanResults.filter(\.breakout52Week).count }
    var flaggedCount: Int { scanResults.filter { $0.score > 0 }.count }
}
