import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ScannerViewModel
    @ObservedObject private var settings = AppSettings.shared

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

            behaviorTab
                .tabItem {
                    Label("Behavior", systemImage: "gearshape")
                }
        }
        .frame(width: 500, height: 560)
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

    @State private var showPassword = false
    @State private var showSecret = false
    @State private var showTOTP = false

    private var kiteCredentialsTab: some View {
        Form {
            Section("Kite Connect API") {
                TextField("API Key", text: $settings.kiteAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack {
                    if showSecret {
                        TextField("API Secret", text: $settings.kiteAPISecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("API Secret", text: $settings.kiteAPISecret)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showSecret.toggle() } label: {
                        Image(systemName: showSecret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Zerodha Login (for auto-login)") {
                TextField("User ID", text: $settings.kiteUserID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack {
                    if showPassword {
                        TextField("Password", text: $settings.kitePassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Password", text: $settings.kitePassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    if showTOTP {
                        TextField("TOTP Secret (base32)", text: $settings.kiteTOTPSecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("TOTP Secret (base32)", text: $settings.kiteTOTPSecret)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showTOTP.toggle() } label: {
                        Image(systemName: showTOTP ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Text("TOTP secret is the base32 key from your Zerodha 2FA setup (NOT the 6-digit code)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    if settings.isTokenValid {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Token valid until midnight")
                                .font(.caption)
                        }
                    } else if settings.hasLoginCredentials {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Token expired — click Login in toolbar or relaunch app")
                                .font(.caption)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Fill all fields above to enable auto-login")
                                .font(.caption)
                        }
                    }
                }

                Text("Credentials are stored in app preferences. All login happens locally on your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Behavior

    private var behaviorTab: some View {
        Form {
            Section("On Launch") {
                Toggle("Auto-login to Kite if token expired", isOn: $settings.autoLoginOnLaunch)
                Toggle("Auto-scan after successful login", isOn: $settings.autoScanAfterLogin)
            }

            Section {
                Text("When both are enabled, the app will automatically login and start scanning every time you open it. No manual steps needed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
