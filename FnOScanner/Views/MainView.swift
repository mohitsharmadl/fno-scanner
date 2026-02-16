import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: ScannerViewModel
    @State private var showLoginSheet = false

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
        .sheet(isPresented: $showLoginSheet) {
            KiteLoginSheet()
                .environmentObject(viewModel)
        }
        .onAppear {
            viewModel.authService.checkTokenValidity()
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        // Auth status indicator
        HStack(spacing: 4) {
            Circle()
                .fill(viewModel.authService.isAuthenticated ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(viewModel.authService.isAuthenticated ? "Connected" : "Not logged in")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if !viewModel.authService.isAuthenticated {
            Button("Login") {
                showLoginSheet = true
            }
        }

        Divider()

        // Scan button
        Button {
            viewModel.startScan()
        } label: {
            Label("Scan", systemImage: "arrow.clockwise")
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

// MARK: - Kite Login Sheet

struct KiteLoginSheet: View {
    @EnvironmentObject var viewModel: ScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var requestToken = ""

    private var loginURL: String {
        "https://kite.trade/connect/login?api_key=\(viewModel.settings.kiteAPIKey)&v=3"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Login to Kite")
                .font(.title2.bold())

            // Step 1
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 1: Open Kite login in browser")
                    .font(.headline)
                Button("Open Kite Login") {
                    if let url = URL(string: loginURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Step 2
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 2: After login, copy the request_token from the redirect URL")
                    .font(.headline)
                Text("The URL will look like:\nhttp://127.0.0.1/?request_token=xxxxxxxx&action=login")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Step 3
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 3: Paste the request_token (or the full URL)")
                    .font(.headline)
                TextField("request_token or full redirect URL", text: $requestToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                if let error = viewModel.authService.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    let token = extractRequestToken(from: requestToken)
                    viewModel.authService.exchangeManualToken(requestToken: token)

                    // Observe for success and dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if viewModel.authService.isAuthenticated {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(requestToken.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.authService.isAuthenticating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    /// Extract request_token from either a raw token or a full URL
    private func extractRequestToken(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it looks like a URL, parse out the request_token param
        if trimmed.contains("request_token=") {
            if let components = URLComponents(string: trimmed),
               let token = components.queryItems?.first(where: { $0.name == "request_token" })?.value {
                return token
            }
            // Fallback: regex-style extraction
            if let range = trimmed.range(of: "request_token=") {
                let after = trimmed[range.upperBound...]
                let token = after.prefix(while: { $0 != "&" && $0 != " " })
                return String(token)
            }
        }

        // Otherwise treat the whole input as the token
        return trimmed
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
