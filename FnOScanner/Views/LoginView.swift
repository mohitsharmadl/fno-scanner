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

            // Status
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
                if settings.kiteAPIKey.isEmpty {
                    Text("Set API credentials in Settings first")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button("Open Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                } else {
                    Button {
                        viewModel.authService.login()
                    } label: {
                        HStack {
                            if viewModel.authService.isAuthenticating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Login with Kite")
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

            Text("Token expires daily at midnight.\nRe-login each morning before trading.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(width: 320)
    }
}
