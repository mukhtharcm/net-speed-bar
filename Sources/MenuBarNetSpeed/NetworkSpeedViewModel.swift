import AppKit
import Combine
import Foundation
import NetSpeedKit
import Network
import SystemConfiguration
import UserNotifications

@MainActor
final class NetworkSpeedViewModel: ObservableObject {
    @Published private(set) var downloadBytesPerSecond: UInt64 = 0
    @Published private(set) var uploadBytesPerSecond: UInt64 = 0
    @Published private(set) var networkName: String?
    @Published private(set) var downloadHistory: [UInt64] = []
    @Published private(set) var uploadHistory: [UInt64] = []
    @Published private(set) var totalDownloadedBytes: UInt64 = 0
    @Published private(set) var totalUploadedBytes: UInt64 = 0
    @Published private(set) var peakDownloadBytesPerSecond: UInt64 = 0
    @Published private(set) var peakUploadBytesPerSecond: UInt64 = 0
    @Published private(set) var downloadDisplayText: String = "0 KB/s"
    @Published private(set) var uploadDisplayText: String = "0 KB/s"
    @Published private(set) var downloadCompactText: String = "0B/s"
    @Published private(set) var uploadCompactText: String = "0B/s"
    @Published private(set) var totalDownloadedDisplayText: String = "0 KB"
    @Published private(set) var totalUploadedDisplayText: String = "0 KB"
    @Published private(set) var peakDownloadDisplayText: String = "0 KB/s"
    @Published private(set) var peakUploadDisplayText: String = "0 KB/s"
    @Published private(set) var latencyMs: Double?
    @Published private(set) var latencyDisplayText: String = "—"
    @Published private(set) var latencyCompactText: String = "—"

    /// Current network path from NWPathMonitor — drives all connection status UI.
    @Published private var networkPath: NWPath?
    /// Best-effort VPN detection via CFNetworkCopySystemProxySettings, updated on each path change.
    @Published private(set) var isVPNActive: Bool = false

    private static let historyCapacity = 60
    /// Cooldown between threshold notifications (seconds)
    private static let notificationCooldown: TimeInterval = 30
    private var lastThresholdNotification: Date = .distantPast
    private var isThresholdCurrentlyExceeded = false

    private let trafficReader = NetworkTrafficReader()
    private let wifiProvider = WiFiDetailsProvider()
    private let settings = SettingsManager.shared
    private let latencyMonitor = LatencyMonitor()
    private var usageTracker: UsageTracker?
    private var refreshTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var settingsCancellables = Set<AnyCancellable>()
    private var lastSnapshot: TrafficSnapshot?
    private var isPopoverVisible = false
    private var isSystemSleeping = false

    var downloadSpeedText: String {
        downloadDisplayText
    }

    var uploadSpeedText: String {
        uploadDisplayText
    }

    enum ConnectionType {
        case wifi, ethernet, vpn, cellular, other, none

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .ethernet: return "cable.connector.horizontal"
            case .vpn: return "lock.shield"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .other: return "network"
            case .none: return "wifi.slash"
            }
        }
    }

    /// Derived from NWPathMonitor for physical type + CFNetworkCopySystemProxySettings for VPN.
    /// NWPathMonitor reliably reports wifi/ethernet/cellular. VPN detection uses system proxy
    /// settings (__SCOPED__ dictionary) to check for tunnel interfaces — no entitlements needed.
    var connectionType: ConnectionType {
        guard let path = networkPath, path.status == .satisfied else { return .none }

        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.cellular) { return .cellular }

        // Path satisfied but not via a standard physical interface.
        // Check cached VPN state from system proxy settings.
        if isVPNActive { return .vpn }

        // Connected via an unrecognized interface (Docker bridge, VM adapter, etc.)
        return .other
    }

    var networkDisplayName: String {
        if connectionType == .wifi, let networkName, !networkName.isEmpty {
            return networkName
        }

        switch connectionType {
        case .wifi: return "Wi-Fi Connected"
        case .ethernet: return "Ethernet Connected"
        case .vpn: return "VPN Connected"
        case .cellular: return "Cellular Connected"
        case .other: return "Connected"
        case .none: return "Network Unavailable"
        }
    }

    var showsConnectedState: Bool {
        connectionType != .none
    }

    var interfaceSummary: String {
        guard let path = networkPath, path.status == .satisfied else {
            return "No active connection"
        }

        let labels = path.availableInterfaces.compactMap { Self.interfaceTypeLabel($0.type) }
        let unique = NSOrderedSet(array: labels).array as! [String]
        var result = unique.isEmpty ? ["Connected"] : unique

        // Append VPN indicator from system proxy settings (independent of NWPath interface types)
        if isVPNActive && !result.contains("VPN") {
            result.append("VPN")
        }

        return result.joined(separator: " · ")
    }

    var downloadCompact: String {
        downloadCompactText
    }

    var uploadCompact: String {
        uploadCompactText
    }

    var totalDownloadedText: String {
        totalDownloadedDisplayText
    }

    var totalUploadedText: String {
        totalUploadedDisplayText
    }

    var peakDownloadText: String {
        peakDownloadDisplayText
    }

    var peakUploadText: String {
        peakUploadDisplayText
    }

    func start() {
        guard refreshTimer == nil, settingsCancellables.isEmpty else { return }

        startPathMonitor()
        refresh()
        startTimer(interval: settings.refreshInterval)

        settings.$refreshInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newInterval in
                self?.startTimer(interval: newInterval)
            }
            .store(in: &settingsCancellables)

        settings.$useBitsPerSecond
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateFormattedOutput()
            }
            .store(in: &settingsCancellables)

        settings.$showNetworkName
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshNetworkName()
            }
            .store(in: &settingsCancellables)

        settings.$latencyEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled {
                    self?.startLatencyMonitor()
                } else {
                    self?.latencyMonitor.stop()
                    self?.latencyMs = nil
                    self?.latencyDisplayText = "—"
                    self?.latencyCompactText = "—"
                }
            }
            .store(in: &settingsCancellables)

        settings.$latencyHost
            .removeDuplicates()
            .sink { [weak self] host in
                let trimmed = host.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                self?.latencyMonitor.updateTarget(host: trimmed)
            }
            .store(in: &settingsCancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.handleSystemWillSleep()
            }
            .store(in: &settingsCancellables)

        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handleSystemDidWake()
            }
            .store(in: &settingsCancellables)

        // Request notification permission if threshold is already enabled
        if settings.speedThresholdEnabled {
            requestNotificationPermission()
        }

        // Start latency monitoring if enabled
        if settings.latencyEnabled {
            startLatencyMonitor()
        }
    }

    private func startLatencyMonitor() {
        latencyMonitor.onStatusUpdate = { [weak self] status in
            switch status {
            case .reachable(let ms):
                self?.latencyMs = ms
                self?.latencyDisplayText = SpeedFormatter.formatLatency(ms)
                self?.latencyCompactText = SpeedFormatter.compactLatency(ms)
            case .unreachable:
                self?.latencyMs = nil
                self?.latencyDisplayText = "Timeout"
                self?.latencyCompactText = "—"
            case .idle, .measuring:
                break
            }
        }
        let host = settings.latencyHost.trimmingCharacters(in: .whitespaces)
        if !host.isEmpty {
            latencyMonitor.updateTarget(host: host)
        }
        latencyMonitor.start(interval: max(settings.refreshInterval * 2, 5))
    }

    private func startTimer(interval: Double) {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard !isSystemSleeping else { return }

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer.tolerance = min(max(interval * 0.15, 0.1), 1.0)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refresh() {
        guard let snapshot = trafficReader.readSnapshot() else {
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            lastSnapshot = nil
            updateFormattedOutput()
            return
        }

        defer {
            lastSnapshot = snapshot
        }

        guard let lastSnapshot else {
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            updateFormattedOutput()
            return
        }

        let interval = max(snapshot.timestamp.timeIntervalSince(lastSnapshot.timestamp), 0.25)
        let delta = snapshot.delta(since: lastSnapshot)
        let receivedDelta = delta.receivedBytes
        let sentDelta = delta.sentBytes

        downloadBytesPerSecond = UInt64(Double(receivedDelta) / interval)
        uploadBytesPerSecond = UInt64(Double(sentDelta) / interval)

        totalDownloadedBytes += receivedDelta
        totalUploadedBytes += sentDelta
        peakDownloadBytesPerSecond = max(peakDownloadBytesPerSecond, downloadBytesPerSecond)
        peakUploadBytesPerSecond = max(peakUploadBytesPerSecond, uploadBytesPerSecond)
        updateFormattedOutput()

        checkSpeedThreshold()

        appendHistory(download: downloadBytesPerSecond, upload: uploadBytesPerSecond)

        // Feed historical usage tracker
        usageTracker?.recordSample(
            downloadDelta: receivedDelta,
            uploadDelta: sentDelta,
            downloadBytesPerSec: downloadBytesPerSecond,
            uploadBytesPerSec: uploadBytesPerSecond
        )
    }

    func setPopoverVisible(_ isVisible: Bool) {
        guard isPopoverVisible != isVisible else { return }
        isPopoverVisible = isVisible
        refreshNetworkName()
    }

    /// Connect the usage tracker so refresh cycles feed it samples.
    func setUsageTracker(_ tracker: UsageTracker) {
        usageTracker = tracker
    }

    private func appendHistory(download: UInt64, upload: UInt64) {
        downloadHistory.append(download)
        uploadHistory.append(upload)
        if downloadHistory.count > Self.historyCapacity {
            downloadHistory.removeFirst(downloadHistory.count - Self.historyCapacity)
        }
        if uploadHistory.count > Self.historyCapacity {
            uploadHistory.removeFirst(uploadHistory.count - Self.historyCapacity)
        }
    }

    /// Returns the notification center if the app has a bundle identifier (required by UNUserNotificationCenter).
    nonisolated private static var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    private func checkSpeedThreshold() {
        guard settings.speedThresholdEnabled else {
            isThresholdCurrentlyExceeded = false
            return
        }
        let thresholdBytes = UInt64(settings.speedThresholdMBps * 1024 * 1024)
        guard thresholdBytes > 0 else {
            isThresholdCurrentlyExceeded = false
            return
        }

        let exceeded = downloadBytesPerSecond > thresholdBytes || uploadBytesPerSecond > thresholdBytes
        guard exceeded else {
            isThresholdCurrentlyExceeded = false
            return
        }

        guard !isThresholdCurrentlyExceeded else { return }

        let now = Date()
        guard now.timeIntervalSince(lastThresholdNotification) >= Self.notificationCooldown else { return }
        lastThresholdNotification = now
        isThresholdCurrentlyExceeded = true

        let direction = downloadBytesPerSecond > thresholdBytes ? "Download" : "Upload"
        let speed = downloadBytesPerSecond > thresholdBytes ? downloadBytesPerSecond : uploadBytesPerSecond

        let content = UNMutableNotificationContent()
        content.title = "High \(direction) Speed"
        content.body = "\(direction) reached \(SpeedFormatter.format(bytesPerSecond: speed, asBits: settings.useBitsPerSecond)) (threshold: \(Int(settings.speedThresholdMBps)) MB/s)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "speed-threshold-\(direction.lowercased())",
            content: content,
            trigger: nil
        )
        Self.notificationCenter?.add(request)
    }

    nonisolated func requestNotificationPermission() {
        guard let center = Self.notificationCenter else { return }

        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // Run VPN detection off the main thread (cheap CF call, no I/O)
            let vpnDetected = Self.detectVPNFromSystemConfiguration()
            Task { @MainActor in
                self?.networkPath = path
                self?.isVPNActive = vpnDetected
                self?.refreshNetworkName()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.mukhtharcm.netspeedbar.path-monitor"))
        pathMonitor = monitor
    }

    /// Only queries CoreWLAN for the SSID — connection type comes from NWPathMonitor.
    private func refreshNetworkName() {
        guard settings.showNetworkName, isPopoverVisible, connectionType == .wifi else {
            networkName = nil
            return
        }

        networkName = wifiProvider.currentSSID()
    }

    private func handleSystemWillSleep() {
        isSystemSleeping = true
        refreshTimer?.invalidate()
        refreshTimer = nil
        isThresholdCurrentlyExceeded = false
        latencyMonitor.stop()
    }

    private func handleSystemDidWake() {
        isSystemSleeping = false
        isThresholdCurrentlyExceeded = false
        lastSnapshot = nil
        refresh()
        startTimer(interval: settings.refreshInterval)
        if settings.latencyEnabled {
            startLatencyMonitor()
        }
    }

    private func updateFormattedOutput() {
        let usesBits = settings.useBitsPerSecond
        downloadDisplayText = SpeedFormatter.format(bytesPerSecond: downloadBytesPerSecond, asBits: usesBits)
        uploadDisplayText = SpeedFormatter.format(bytesPerSecond: uploadBytesPerSecond, asBits: usesBits)
        downloadCompactText = SpeedFormatter.compactFormat(bytesPerSecond: downloadBytesPerSecond, asBits: usesBits)
        uploadCompactText = SpeedFormatter.compactFormat(bytesPerSecond: uploadBytesPerSecond, asBits: usesBits)
        totalDownloadedDisplayText = SpeedFormatter.formatByteCount(totalDownloadedBytes)
        totalUploadedDisplayText = SpeedFormatter.formatByteCount(totalUploadedBytes)
        peakDownloadDisplayText = SpeedFormatter.format(bytesPerSecond: peakDownloadBytesPerSecond, asBits: usesBits)
        peakUploadDisplayText = SpeedFormatter.format(bytesPerSecond: peakUploadBytesPerSecond, asBits: usesBits)
    }

    var latencyCompact: String {
        latencyCompactText
    }

    /// Best-effort VPN detection via CFNetworkCopySystemProxySettings.
    /// Checks the __SCOPED__ proxy dictionary for tunnel interface keys (utun, tun, tap, ppp, ipsec).
    /// Unlike raw getifaddrs, scoped proxy entries only appear for interfaces with active proxy
    /// configurations — much more reliable than checking interface UP/RUNNING flags.
    /// Requires no special entitlements. ~80% accurate for common VPN configurations.
    nonisolated private static func detectVPNFromSystemConfiguration() -> Bool {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = proxySettings["__SCOPED__"] as? [String: Any] else {
            return false
        }
        let vpnPrefixes = ["utun", "tun", "tap", "ppp", "ipsec"]
        return scoped.keys.contains { key in
            vpnPrefixes.contains { prefix in key.hasPrefix(prefix) }
        }
    }

    private static func interfaceTypeLabel(_ type: NWInterface.InterfaceType) -> String? {
        switch type {
        case .wifi: return "Wi-Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .other: return nil  // Could be Docker, VM, bridge — not necessarily VPN
        case .loopback: return nil
        @unknown default: return nil
        }
    }
}
