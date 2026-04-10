import SwiftUI

@main
struct MenuBarNetSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = NetworkSpeedViewModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: viewModel)
        } label: {
            HStack(spacing: 1) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .semibold))
                Text(viewModel.downloadCompact)
                    .monospacedDigit()
                    .padding(.trailing, 3)

                Image(systemName: "arrow.up")
                    .font(.system(size: 8, weight: .semibold))
                Text(viewModel.uploadCompact)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
        }
        .menuBarExtraStyle(.window)
    }
}
