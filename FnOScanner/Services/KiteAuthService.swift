import Foundation
import CryptoKit

/// Captures redirect URLs during the Kite OAuth flow to extract request_token
private class RedirectCaptureDelegate: NSObject, URLSessionTaskDelegate {
    var capturedLocation: String?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let location = request.url?.absoluteString ?? ""
        if location.contains("request_token=") {
            capturedLocation = location
            completionHandler(nil) // stop — we got what we need
        } else {
            completionHandler(request) // keep following
        }
    }
}

@MainActor
class KiteAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var isAuthenticating = false
    @Published var loginStep: String = ""

    private let settings = AppSettings.shared

    override init() {
        super.init()
        isAuthenticated = settings.isTokenValid
    }

    // MARK: - Headless Login (no browser needed)

    func headlessLogin() async {
        guard settings.hasLoginCredentials else {
            authError = "Missing credentials — fill all fields in Settings > Kite API"
            return
        }

        isAuthenticating = true
        authError = nil

        let apiKey = settings.kiteAPIKey
        let apiSecret = settings.kiteAPISecret
        let userID = settings.kiteUserID
        let password = settings.kitePassword
        let totpSecret = settings.kiteTOTPSecret

        // Shared cookie storage across both sessions
        let cookieStorage = HTTPCookieStorage.shared
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookieStorage
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config)

        do {
            // Step 1: Load login page (get session cookies)
            loginStep = "Loading login page..."
            let loginURL = "https://kite.trade/connect/login?api_key=\(apiKey)&v=3"
            var req = URLRequest(url: URL(string: loginURL)!)
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            let _ = try await session.data(for: req)

            // Step 2: POST credentials
            loginStep = "Submitting credentials..."
            var loginReq = URLRequest(url: URL(string: "https://kite.zerodha.com/api/login")!)
            loginReq.httpMethod = "POST"
            loginReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            loginReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            loginReq.httpBody = "user_id=\(urlEncode(userID))&password=\(urlEncode(password))".data(using: .utf8)

            let (loginData, _) = try await session.data(for: loginReq)
            guard let loginJSON = try JSONSerialization.jsonObject(with: loginData) as? [String: Any],
                  loginJSON["status"] as? String == "success",
                  let loginDict = loginJSON["data"] as? [String: Any],
                  let requestID = loginDict["request_id"] as? String else {
                let body = String(data: loginData, encoding: .utf8) ?? "Unknown"
                authError = "Login failed: \(body)"
                isAuthenticating = false
                loginStep = ""
                return
            }

            // Step 3: Generate TOTP and submit 2FA
            loginStep = "Submitting TOTP..."
            guard let totpCode = TOTPGenerator.generate(secret: totpSecret) else {
                authError = "Failed to generate TOTP code"
                isAuthenticating = false
                loginStep = ""
                return
            }

            var tfaReq = URLRequest(url: URL(string: "https://kite.zerodha.com/api/twofa")!)
            tfaReq.httpMethod = "POST"
            tfaReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            tfaReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            tfaReq.httpBody = "user_id=\(urlEncode(userID))&request_id=\(urlEncode(requestID))&twofa_value=\(totpCode)&twofa_type=totp".data(using: .utf8)

            let (tfaData, _) = try await session.data(for: tfaReq)
            guard let tfaJSON = try JSONSerialization.jsonObject(with: tfaData) as? [String: Any],
                  tfaJSON["status"] as? String == "success" else {
                let body = String(data: tfaData, encoding: .utf8) ?? "Unknown"
                authError = "2FA failed: \(body)"
                isAuthenticating = false
                loginStep = ""
                return
            }

            // Step 4: Follow redirects to capture request_token
            loginStep = "Getting request token..."
            let redirectDelegate = RedirectCaptureDelegate()
            let redirectConfig = URLSessionConfiguration.ephemeral
            redirectConfig.httpCookieStorage = cookieStorage
            redirectConfig.httpCookieAcceptPolicy = .always
            let redirectSession = URLSession(configuration: redirectConfig, delegate: redirectDelegate, delegateQueue: nil)

            var redirectReq = URLRequest(url: URL(string: loginURL)!)
            redirectReq.setValue(ua, forHTTPHeaderField: "User-Agent")

            // This will follow redirects until our delegate stops it
            let _ = try? await redirectSession.data(for: redirectReq)

            guard let capturedURL = redirectDelegate.capturedLocation,
                  let components = URLComponents(string: capturedURL),
                  let requestToken = components.queryItems?.first(where: { $0.name == "request_token" })?.value else {
                authError = "Could not get request token from Kite redirect"
                isAuthenticating = false
                loginStep = ""
                return
            }

            // Step 5: Exchange request_token for access_token
            loginStep = "Exchanging for access token..."
            await exchangeToken(requestToken: requestToken)
            loginStep = ""
            isAuthenticating = false

        } catch {
            authError = "Login error: \(error.localizedDescription)"
            isAuthenticating = false
            loginStep = ""
        }
    }

    // MARK: - Token Exchange

    private func exchangeToken(requestToken: String) async {
        let apiKey = settings.kiteAPIKey
        let apiSecret = settings.kiteAPISecret
        let checksum = sha256("\(apiKey)\(requestToken)\(apiSecret)")

        let url = URL(string: "https://api.kite.trade/session/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "api_key=\(apiKey)&request_token=\(requestToken)&checksum=\(checksum)".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown"
                authError = "Token exchange failed: \(body)"
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dataDict = json?["data"] as? [String: Any],
                  let accessToken = dataDict["access_token"] as? String else {
                authError = "Could not parse access token"
                return
            }

            settings.kiteAccessToken = accessToken
            settings.kiteAccessTokenDate = Date()
            isAuthenticated = true
            authError = nil
            print("Kite login successful, token: \(accessToken.prefix(8))...")
        } catch {
            authError = "Network error: \(error.localizedDescription)"
        }
    }

    // MARK: - Logout

    func logout() {
        settings.kiteAccessToken = ""
        settings.kiteAccessTokenDate = nil
        isAuthenticated = false
    }

    func checkTokenValidity() {
        isAuthenticated = settings.isTokenValid
    }

    // MARK: - Helpers

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}
