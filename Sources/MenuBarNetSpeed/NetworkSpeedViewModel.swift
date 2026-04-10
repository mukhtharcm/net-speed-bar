import AppKit
import Combine
import Foundation
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

    /// Current network path from NWPathMonitor — drives all connection status UI.
    @Published private var networkPath: NWPath?
    /// Best-effort VPN detection via CFNetworkCopySystemProxySettings, updated on each path change.
    @Published private(set) var isVPNActive: Bool = false

    private static let historyCapacity = 60
    /// Cooldown between threshold notifications (seconds)
    private static let notificationCooldown: TimeInterval = 30
    private var lastThresholdNotification: Date = .distantPast

    private let trafficReader = NetworkTrafficReader()
    private let wifiProvider = WiFiDetailsProvider()
    private let settings = SettingsManager.shared
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

        // Handle 32-bit counter rollover (wraps at ~4 GB)
        let uint32Max = UInt64(UInt32.max)
        let receivedDelta: UInt64
        if snapshot.receivedBytes >= lastSnapshot.receivedBytes {
            receivedDelta = snapshot.receivedBytes - lastSnapshot.receivedBytes
        } else {
            receivedDelta = (uint32Max - lastSnapshot.receivedBytes) + snapshot.receivedBytes
        }
        let sentDelta: UInt64
        if snapshot.sentBytes >= lastSnapshot.sentBytes {
            sentDelta = snapshot.sentBytes - lastSnapshot.sentBytes
        } else {
            sentDelta = (uint32Max - lastSnapshot.sentBytes) + snapshot.sentBytes
        }

        downloadBytesPerSecond = UInt64(Double(receivedDelta) / interval)
        uploadBytesPerSecond = UInt64(Double(sentDelta) / interval)

        totalDownloadedBytes += receivedDelta
        totalUploadedBytes += sentDelta
        peakDownloadBytesPerSecond = max(peakDownloadBytesPerSecond, downloadBytesPerSecond)
        peakUploadBytesPerSecond = max(peakUploadBytesPerSecond, uploadBytesPerSecond)
        updateFormattedOutput()

        checkSpeedThreshold()

        appendHistory(download: downloadBytesPerSecond, upload: uploadBytesPerSecond)
    }

    func setPopoverVisible(_ isVisible: Bool) {
        guard isPopoverVisible != isVisible else { return }
        isPopoverVisible = isVisible
        refreshNetworkName()
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
        guard settings.speedThresholdEnabled else { return }
        let thresholdBytes = UInt64(settings.speedThresholdMBps * 1024 * 1024)
        guard thresholdBytes > 0 else { return }

        let exceeded = downloadBytesPerSecond > thresholdBytes || uploadBytesPerSecond > thresholdBytes
        guard exceeded else { return }

        let now = Date()
        guard now.timeIntervalSince(lastThresholdNotification) >= Self.notificationCooldown else { return }
        lastThresholdNotification = now

        let direction = downloadBytesPerSecond > thresholdBytes ? "Download" : "Upload"
        let speed = downloadBytesPerSecond > thresholdBytes ? downloadBytesPerSecond : uploadBytesPerSecond

        let content = UNMutableNotificationContent()
        content.title = "High \(direction) Speed"
        content.body = "\(direction) reached \(Self.format(bytesPerSecond: speed, asBits: settings.useBitsPerSecond)) (threshold: \(Int(settings.speedThresholdMBps)) MB/s)"
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

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

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
    }

    private func handleSystemDidWake() {
        isSystemSleeping = false
        lastSnapshot = nil
        refresh()
        startTimer(interval: settings.refreshInterval)
    }

    private func updateFormattedOutput() {
        let usesBits = settings.useBitsPerSecond
        downloadDisplayText = Self.format(bytesPerSecond: downloadBytesPerSecond, asBits: usesBits)
        uploadDisplayText = Self.format(bytesPerSecond: uploadBytesPerSecond, asBits: usesBits)
        downloadCompactText = Self.compactFormat(bytesPerSecond: downloadBytesPerSecond, asBits: usesBits)
        uploadCompactText = Self.compactFormat(bytesPerSecond: uploadBytesPerSecond, asBits: usesBits)
        totalDownloadedDisplayText = Self.byteCountFormatter.string(fromByteCount: Int64(clamping: totalDownloadedBytes))
        totalUploadedDisplayText = Self.byteCountFormatter.string(fromByteCount: Int64(clamping: totalUploadedBytes))
        peakDownloadDisplayText = Self.format(bytesPerSecond: peakDownloadBytesPerSecond, asBits: usesBits)
        peakUploadDisplayText = Self.format(bytesPerSecond: peakUploadBytesPerSecond, asBits: usesBits)
    }

    private static func format(bytesPerSecond: UInt64, asBits: Bool = false) -> String {
        if asBits {
            return formatBits(bytesPerSecond: bytesPerSecond)
        }
        return "\(byteCountFormatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    private static func formatBits(bytesPerSecond: UInt64) -> String {
        let bitsPerSecond = Double(bytesPerSecond) * 8
        let units = ["bps", "Kbps", "Mbps", "Gbps"]
        var value = bitsPerSecond
        var unitIndex = 0
        while value >= 1000 && unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(value)) \(units[0])"
        }
        let precision = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.\(precision)f %@", value, units[unitIndex])
    }

    private static func compactFormat(bytesPerSecond: UInt64, asBits: Bool = false) -> String {
        if asBits {
            return compactFormatBits(bytesPerSecond: bytesPerSecond)
        }
        if bytesPerSecond < 1024 {
            return "\(bytesPerSecond)B/s"
        }

        let units = ["KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = -1

        repeat {
            value /= 1024
            unitIndex += 1
        } while value >= 1024 && unitIndex < units.count - 1

        let precision = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.\(precision)f%@", value, units[unitIndex])
    }

    private static func compactFormatBits(bytesPerSecond: UInt64) -> String {
        let bitsPerSecond = Double(bytesPerSecond) * 8
        if bitsPerSecond < 1000 {
            return "\(Int(bitsPerSecond))bps"
        }
        let units = ["Kb", "Mb", "Gb"]
        var value = bitsPerSecond
        var unitIndex = -1
        repeat {
            value /= 1000
            unitIndex += 1
        } while value >= 1000 && unitIndex < units.count - 1
        let precision = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.\(precision)f%@", value, units[unitIndex])
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
