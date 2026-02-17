import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: ScannerViewModel
    @State private var hasAttemptedAutoLogin = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ScanResultsTable()
        } detail: {
            if let selected = viewModel.selectedStock {
                StockDetailView(result: selected)
            } else {
                ContentUnavailableView("Select a Stock", systemImage: "chart.line.uptrend.xyaxis", description: Text("Select a stock from the table to view details"))
            }
        }
        .navigationTitle("FnO Scanner")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarContent
            }
        }
        .onAppear {
            guard !hasAttemptedAutoLogin else { return }
            hasAttemptedAutoLogin = true
            viewModel.authService.checkTokenValidity()

            // Auto-login if token expired and credentials exist
            if !viewModel.authService.isAuthenticated && viewModel.settings.autoLoginOnLaunch && viewModel.settings.hasLoginCredentials {
                Task {
                    await viewModel.authService.headlessLogin()
                    if viewModel.authService.isAuthenticated && viewModel.settings.autoScanAfterLogin {
                        viewModel.startScan()
                    }
                }
            } else if viewModel.authService.isAuthenticated && viewModel.settings.autoScanAfterLogin && viewModel.scanResults.isEmpty {
                viewModel.startScan()
            }
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        // Auth status
        if viewModel.authService.isAuthenticating {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text(viewModel.authService.loginStep)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.authService.isAuthenticated ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(viewModel.authService.isAuthenticated ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        // Login / Refresh token button
        if !viewModel.authService.isAuthenticated && !viewModel.authService.isAuthenticating {
            Button {
                Task {
                    await viewModel.authService.headlessLogin()
                    if viewModel.authService.isAuthenticated && viewModel.settings.autoScanAfterLogin {
                        viewModel.startScan()
                    }
                }
            } label: {
                Label("Login", systemImage: "key.fill")
            }
            .disabled(!viewModel.settings.hasLoginCredentials)
            .help(viewModel.settings.hasLoginCredentials ? "Login to Kite" : "Set credentials in Settings first")
        }

        if viewModel.authService.isAuthenticated {
            Button {
                Task {
                    await viewModel.authService.headlessLogin()
                }
            } label: {
                Label("Refresh Token", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Get a fresh Kite token")
        }

        Divider()

        // Scan button
        Button {
            viewModel.startScan()
        } label: {
            Label("Scan", systemImage: "magnifyingglass")
        }
        .disabled(viewModel.isScanning || !viewModel.authService.isAuthenticated)

        // Last scan time
        if let lastScan = viewModel.lastScanTime {
            Text(lastScan, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var viewModel: ScannerViewModel

    var body: some View {
        List {
            Section("Filters") {
                ForEach(ScannerViewModel.ScanFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.activeFilter = filter
                    } label: {
                        HStack {
                            Label(filter.rawValue, systemImage: iconFor(filter))
                            Spacer()
                            Text("\(countFor(filter))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewModel.activeFilter == filter ? Color.accentColor.opacity(0.12) : Color.clear)
                            .padding(.horizontal, -8)
                    )
                }
            }

            Section("Sort By") {
                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(ScannerViewModel.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if viewModel.isScanning {
                Section("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: viewModel.progressPercent)
                        Text(viewModel.scanProgressText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let error = viewModel.authService.authError {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("Stats") {
                StatRow(label: "Total Stocks", value: "\(viewModel.totalStocks)")
                StatRow(label: "Confluence", value: "\(viewModel.confluenceCount)", color: .purple)
                StatRow(label: "Volume Spikes", value: "\(viewModel.volumeSpikeCount)", color: .red)
                StatRow(label: "Near EMA", value: "\(viewModel.nearEMACount)", color: .blue)
                StatRow(label: "Breakouts", value: "\(viewModel.breakoutCount)", color: .green)
                StatRow(label: "Flagged", value: "\(viewModel.flaggedCount)", color: .orange)
            }

            Section {
                Button {
                    viewModel.scannerService.clearCache()
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $viewModel.searchText, prompt: "Search stocks...")
    }

    private func iconFor(_ filter: ScannerViewModel.ScanFilter) -> String {
        switch filter {
        case .all: return "list.bullet"
        case .confluencePullback: return "arrow.turn.down.right"
        case .volumeSpikes: return "chart.bar.fill"
        case .nearEMA: return "line.3.horizontal"
        case .breakouts: return "arrow.up.right"
        case .flagged: return "flag.fill"
        }
    }

    private func countFor(_ filter: ScannerViewModel.ScanFilter) -> Int {
        switch filter {
        case .all: return viewModel.totalStocks
        case .confluencePullback: return viewModel.confluenceCount
        case .volumeSpikes: return viewModel.volumeSpikeCount
        case .nearEMA: return viewModel.nearEMACount
        case .breakouts: return viewModel.breakoutCount
        case .flagged: return viewModel.flaggedCount
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(color)
        }
    }
}
