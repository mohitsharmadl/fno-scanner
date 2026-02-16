import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
class KiteAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var isAuthenticating = false

    private let settings = AppSettings.shared

    override init() {
        super.init()
        isAuthenticated = settings.isTokenValid
    }

    func login() {
        guard !settings.kiteAPIKey.isEmpty, !settings.kiteAPISecret.isEmpty else {
            authError = "Set API key & secret in Settings first"
            return
        }

        isAuthenticating = true
        authError = nil

        let urlString = "https://kite.trade/connect/login?api_key=\(settings.kiteAPIKey)&v=3"
        guard let url = URL(string: urlString) else {
            authError = "Invalid login URL"
            isAuthenticating = false
            return
        }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "fnoscanner"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthenticating = false

                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.authError = "Login cancelled"
                    } else {
                        self.authError = error.localizedDescription
                    }
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let requestToken = components.queryItems?.first(where: { $0.name == "request_token" })?.value else {
                    self.authError = "Could not extract request token from callback"
                    return
                }

                await self.exchangeToken(requestToken: requestToken)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// Exchange a manually-pasted request token
    func exchangeManualToken(requestToken: String) {
        let trimmed = requestToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            authError = "Request token is empty"
            return
        }
        isAuthenticating = true
        authError = nil
        Task {
            await exchangeToken(requestToken: trimmed)
            isAuthenticating = false
        }
    }

    private func exchangeToken(requestToken: String) async {
        let apiKey = settings.kiteAPIKey
        let apiSecret = settings.kiteAPISecret
        let checksum = sha256("\(apiKey)\(requestToken)\(apiSecret)")

        let url = URL(string: "https://api.kite.trade/session/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "api_key=\(apiKey)&request_token=\(requestToken)&checksum=\(checksum)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                authError = "Token exchange failed: \(errorBody)"
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dataDict = json?["data"] as? [String: Any],
                  let accessToken = dataDict["access_token"] as? String else {
                authError = "Could not parse access token from response"
                return
            }

            settings.kiteAccessToken = accessToken
            settings.kiteAccessTokenDate = Date()
            isAuthenticated = true
            authError = nil
        } catch {
            authError = "Network error: \(error.localizedDescription)"
        }
    }

    func logout() {
        settings.kiteAccessToken = ""
        settings.kiteAccessTokenDate = nil
        isAuthenticated = false
    }

    func checkTokenValidity() {
        isAuthenticated = settings.isTokenValid
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

extension KiteAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
