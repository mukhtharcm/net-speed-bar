import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush usage data to disk before quitting
        Task { @MainActor in
            UsageTracker.shared.flush()
        }
    }
}
