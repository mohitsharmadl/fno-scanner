import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("emaProximityPercent") var emaProximityPercent: Double = 1.5
    @AppStorage("volumeMultiplier") var volumeMultiplier: Double = 2.0
    @AppStorage("breakout52WeekPercent") var breakout52WeekPercent: Double = 5.0
    @AppStorage("autoRefreshMinutes") var autoRefreshMinutes: Int = 15
    @AppStorage("confluenceLookbackDays") var confluenceLookbackDays: Int = 60
    @AppStorage("confluenceMinPullbackPercent") var confluenceMinPullbackPercent: Double = 2.0
    @AppStorage("confluenceMaxPullbackPercent") var confluenceMaxPullbackPercent: Double = 20.0

    @AppStorage("kiteAPIKey") var kiteAPIKey: String = ""
    @AppStorage("kiteAPISecret") var kiteAPISecret: String = ""
    @AppStorage("kiteAccessToken") var kiteAccessToken: String = ""
    @AppStorage("kiteUserID") var kiteUserID: String = ""
    @AppStorage("kitePassword") var kitePassword: String = ""
    @AppStorage("kiteTOTPSecret") var kiteTOTPSecret: String = ""
    @AppStorage("autoLoginOnLaunch") var autoLoginOnLaunch: Bool = true
    @AppStorage("autoScanAfterLogin") var autoScanAfterLogin: Bool = true

    var hasLoginCredentials: Bool {
        !kiteAPIKey.isEmpty && !kiteAPISecret.isEmpty &&
        !kiteUserID.isEmpty && !kitePassword.isEmpty && !kiteTOTPSecret.isEmpty
    }

    var kiteAccessTokenDate: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: "kiteAccessTokenTimestamp")
            guard ts > 0 else { return nil }
            return Date(timeIntervalSince1970: ts)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "kiteAccessTokenTimestamp")
            } else {
                UserDefaults.standard.removeObject(forKey: "kiteAccessTokenTimestamp")
            }
            objectWillChange.send()
        }
    }

    var isTokenValid: Bool {
        guard !kiteAccessToken.isEmpty, let tokenDate = kiteAccessTokenDate else { return false }
        return Calendar.current.isDateInToday(tokenDate)
    }
}
