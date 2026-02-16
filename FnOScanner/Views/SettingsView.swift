import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ScannerViewModel
    @ObservedObject private var settings = AppSettings.shared

    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var showSecret = false

    var body: some View {
        TabView {
            scanSettingsTab
                .tabItem {
                    Label("Scan Settings", systemImage: "slider.horizontal.3")
                }

            kiteCredentialsTab
                .tabItem {
                    Label("Kite API", systemImage: "key.fill")
                }
        }
        .frame(width: 480, height: 500)
        .onAppear {
            apiKey = settings.kiteAPIKey
            apiSecret = settings.kiteAPISecret
        }
    }

    // MARK: - Scan Settings

    private var scanSettingsTab: some View {
        Form {
            Section("EMA Proximity") {
                HStack {
                    Text("Threshold:")
                    Slider(value: $settings.emaProximityPercent, in: 0.5...5.0, step: 0.1)
                    Text(String(format: "%.1f%%", settings.emaProximityPercent))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                }
                Text("Stocks within this % of any EMA will be flagged")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Volume Spike") {
                HStack {
                    Text("Multiplier:")
                    Slider(value: $settings.volumeMultiplier, in: 1.5...5.0, step: 0.5)
                    Text(String(format: "%.1fx", settings.volumeMultiplier))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                }
                Text("Volume must be this many times the 20-day average")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("52-Week Breakout") {
                HStack {
                    Text("Proximity:")
                    Slider(value: $settings.breakout52WeekPercent, in: 1.0...10.0, step: 0.5)
                    Text(String(format: "%.1f%%", settings.breakout52WeekPercent))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                }
                Text("Flag stocks within this % of their 52-week high")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Confluence Pullback") {
                HStack {
                    Text("Lookback:")
                    Picker("", selection: $settings.confluenceLookbackDays) {
                        Text("30 days").tag(30)
                        Text("45 days").tag(45)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                Text("How far back to look for a breakout above prior resistance")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Min pullback:")
                    Slider(value: $settings.confluenceMinPullbackPercent, in: 1.0...5.0, step: 0.5)
                    Text(String(format: "%.1f%%", settings.confluenceMinPullbackPercent))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Max pullback:")
                    Slider(value: $settings.confluenceMaxPullbackPercent, in: 10.0...30.0, step: 5.0)
                    Text(String(format: "%.0f%%", settings.confluenceMaxPullbackPercent))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                }
                Text("Pullback range from recent high (too shallow = not a pullback, too deep = trend broken)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Auto Refresh") {
                Picker("Interval:", selection: $settings.autoRefreshMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }
                Text("Only refreshes during market hours (9:15 AM - 3:30 PM IST)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Kite Credentials

    private var kiteCredentialsTab: some View {
        Form {
            Section("Kite Connect Credentials") {
                TextField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if showSecret {
                        TextField("API Secret", text: $apiSecret)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Secret", text: $apiSecret)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showSecret.toggle()
                    } label: {
                        Image(systemName: showSecret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                HStack {
                    Button("Save") {
                        settings.kiteAPIKey = apiKey
                        settings.kiteAPISecret = apiSecret
                    }
                    .buttonStyle(.borderedProminent)

                    if settings.isTokenValid {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Token valid")
                                .font(.caption)
                        }
                    }
                }

                Text("Credentials are stored securely in macOS Keychain")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Setup Instructions") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Log in to Kite Connect developer portal")
                    Text("2. Copy your API Key and Secret")
                    Text("3. Paste them above and click Save")
                    Text("4. Use the Login button in the toolbar to authenticate")
                    Text("5. You'll need to re-login daily (tokens expire at midnight)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
