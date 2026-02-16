import SwiftUI

@main
struct FnOScannerApp: App {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(viewModel)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 750)

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}
