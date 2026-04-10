import SwiftUI

@main
struct MenuBarNetSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = NetworkSpeedViewModel()
    @StateObject private var settings = SettingsManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: viewModel, settings: settings)
        } label: {
            HStack(spacing: 1) {
                if settings.menuBarDisplayMode != .uploadOnly {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .semibold))
                    Text(viewModel.downloadCompact)
                        .monospacedDigit()
                        .padding(.trailing, settings.menuBarDisplayMode == .both ? 3 : 0)
                }
                if settings.menuBarDisplayMode != .downloadOnly {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .semibold))
                    Text(viewModel.uploadCompact)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
        }
        .menuBarExtraStyle(.window)
    }
}
