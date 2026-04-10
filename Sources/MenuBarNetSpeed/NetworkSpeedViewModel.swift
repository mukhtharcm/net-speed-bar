import Combine
import Foundation

@MainActor
final class NetworkSpeedViewModel: ObservableObject {
    @Published private(set) var downloadBytesPerSecond: UInt64 = 0
    @Published private(set) var uploadBytesPerSecond: UInt64 = 0
    @Published private(set) var networkName: String?
    @Published private(set) var activeInterfaces: [String] = []
    @Published private(set) var wifiInterfaceName: String?
    @Published private(set) var downloadHistory: [UInt64] = []
    @Published private(set) var uploadHistory: [UInt64] = []
    @Published private(set) var totalDownloadedBytes: UInt64 = 0
    @Published private(set) var totalUploadedBytes: UInt64 = 0
    @Published private(set) var peakDownloadBytesPerSecond: UInt64 = 0
    @Published private(set) var peakUploadBytesPerSecond: UInt64 = 0

    private static let historyCapacity = 60

    private let trafficReader = NetworkTrafficReader()
    private let wifiProvider = WiFiDetailsProvider()
    private let settings = SettingsManager.shared
    private var timerCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var lastSnapshot: TrafficSnapshot?

    var downloadSpeedText: String {
        Self.format(bytesPerSecond: downloadBytesPerSecond, asBits: settings.useBitsPerSecond)
    }

    var uploadSpeedText: String {
        Self.format(bytesPerSecond: uploadBytesPerSecond, asBits: settings.useBitsPerSecond)
    }

    var networkDisplayName: String {
        if let networkName, !networkName.isEmpty {
            return networkName
        }

        if let wifiInterfaceName, activeInterfaces.contains(wifiInterfaceName) {
            return "Wi-Fi Connected"
        }

        if let primaryInterface = activeInterfaces.first {
            return "Connected via \(Self.interfaceDisplayName(for: primaryInterface))"
        }

        return "Network Unavailable"
    }

    var interfaceSummary: String {
        if activeInterfaces.isEmpty {
            return "No active interface detected"
        }

        let names = activeInterfaces.joined(separator: ", ")
        return "Interface\(activeInterfaces.count == 1 ? "" : "s"): \(names)"
    }

    var menuBarTitle: String {
        "↓\(Self.compactFormat(bytesPerSecond: downloadBytesPerSecond)) ↑\(Self.compactFormat(bytesPerSecond: uploadBytesPerSecond))"
    }

    var downloadCompact: String {
        Self.compactFormat(bytesPerSecond: downloadBytesPerSecond, asBits: settings.useBitsPerSecond)
    }

    var uploadCompact: String {
        Self.compactFormat(bytesPerSecond: uploadBytesPerSecond, asBits: settings.useBitsPerSecond)
    }

    var totalDownloadedText: String {
        Self.byteCountFormatter.string(fromByteCount: Int64(clamping: totalDownloadedBytes))
    }

    var totalUploadedText: String {
        Self.byteCountFormatter.string(fromByteCount: Int64(clamping: totalUploadedBytes))
    }

    var peakDownloadText: String {
        Self.format(bytesPerSecond: peakDownloadBytesPerSecond, asBits: settings.useBitsPerSecond)
    }

    var peakUploadText: String {
        Self.format(bytesPerSecond: peakUploadBytesPerSecond, asBits: settings.useBitsPerSecond)
    }

    func start() {
        guard timerCancellable == nil else { return }

        refresh()
        startTimer(interval: settings.refreshInterval)

        settingsCancellable = settings.$refreshInterval
            .sink { [weak self] newInterval in
                self?.startTimer(interval: newInterval)
            }
    }

    private func startTimer(interval: Double) {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    private func refresh() {
        if settings.showNetworkName {
            let wifiDetails = wifiProvider.currentDetails()
            networkName = wifiDetails.ssid
            wifiInterfaceName = wifiDetails.interfaceName
        } else {
            networkName = nil
            wifiInterfaceName = nil
        }

        guard let snapshot = trafficReader.readSnapshot() else {
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            activeInterfaces = []
            lastSnapshot = nil
            return
        }

        activeInterfaces = snapshot.interfaceNames

        defer {
            lastSnapshot = snapshot
        }

        guard let lastSnapshot else {
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
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

        appendHistory(download: downloadBytesPerSecond, upload: uploadBytesPerSecond)
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

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

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

    private static func interfaceDisplayName(for interfaceName: String) -> String {
        if interfaceName.hasPrefix("en") {
            return "Wi-Fi / Ethernet"
        }

        if interfaceName.hasPrefix("utun") {
            return "VPN"
        }

        if interfaceName.hasPrefix("bridge") {
            return "Bridge"
        }

        if interfaceName.hasPrefix("pdp_ip") {
            return "Cellular"
        }

        return interfaceName
    }
}
