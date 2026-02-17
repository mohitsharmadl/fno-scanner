import SwiftUI

struct LoginView: View {
    @EnvironmentObject var viewModel: ScannerViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(viewModel.authService.isAuthenticated ? .green : .secondary)

            Text("Kite Authentication")
                .font(.title2.bold())

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.authService.isAuthenticated ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(viewModel.authService.isAuthenticated ? "Authenticated" : "Not authenticated")
                    .foregroundColor(viewModel.authService.isAuthenticated ? .green : .red)
            }
            .font(.body)

            if let tokenDate = settings.kiteAccessTokenDate {
                Text("Last login: \(tokenDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.authService.isAuthenticating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(viewModel.authService.loginStep)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = viewModel.authService.authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Divider()
                .frame(width: 200)

            if !viewModel.authService.isAuthenticated {
                if !settings.hasLoginCredentials {
                    Text("Set credentials in Settings > Kite API")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button("Open Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                } else {
                    Button {
                        Task {
                            await viewModel.authService.headlessLogin()
                        }
                    } label: {
                        HStack {
                            if viewModel.authService.isAuthenticating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Login to Kite")
                        }
                        .frame(width: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.authService.isAuthenticating)
                }
            } else {
                Button("Logout") {
                    viewModel.authService.logout()
                }
                .buttonStyle(.bordered)
            }

            Text("Auto-login is \(settings.autoLoginOnLaunch ? "ON" : "OFF").\nTokens expire daily at midnight IST.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(width: 320)
    }
}
