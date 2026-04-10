import Combine
import Foundation
import ServiceManagement

enum MenuBarDisplayMode: Int, CaseIterable, Identifiable, Sendable {
    case both = 0
    case downloadOnly = 1
    case uploadOnly = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .both: "Download & Upload"
        case .downloadOnly: "Download Only"
        case .uploadOnly: "Upload Only"
        }
    }
}

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var refreshInterval: Double {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLogin()
        }
    }

    @Published var showNetworkName: Bool {
        didSet { UserDefaults.standard.set(showNetworkName, forKey: Keys.showNetworkName) }
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let launchAtLogin = "launchAtLogin"
        static let showNetworkName = "showNetworkName"
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.refreshInterval: 1.0,
            Keys.menuBarDisplayMode: MenuBarDisplayMode.both.rawValue,
            Keys.launchAtLogin: false,
            Keys.showNetworkName: true,
        ])

        self.refreshInterval = defaults.double(forKey: Keys.refreshInterval)
        self.menuBarDisplayMode =
            MenuBarDisplayMode(rawValue: defaults.integer(forKey: Keys.menuBarDisplayMode)) ?? .both
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showNetworkName = defaults.bool(forKey: Keys.showNetworkName)
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // May not work outside a proper .app bundle
        }
    }
}
