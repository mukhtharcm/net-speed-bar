import Combine
import Foundation

@MainActor
final class NetworkSpeedViewModel: ObservableObject {
    @Published private(set) var downloadBytesPerSecond: UInt64 = 0
    @Published private(set) var uploadBytesPerSecond: UInt64 = 0
    @Published private(set) var networkName: String?
    @Published private(set) var activeInterfaces: [String] = []

    private let trafficReader = NetworkTrafficReader()
    private let wifiProvider = WiFiDetailsProvider()
    private var timerCancellable: AnyCancellable?
    private var lastSnapshot: TrafficSnapshot?

    var downloadSpeedText: String {
        Self.format(bytesPerSecond: downloadBytesPerSecond)
    }

    var uploadSpeedText: String {
        Self.format(bytesPerSecond: uploadBytesPerSecond)
    }

    var networkDisplayName: String {
        if let networkName, !networkName.isEmpty {
            return networkName
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
        Self.compactFormat(bytesPerSecond: downloadBytesPerSecond)
    }

    var uploadCompact: String {
        Self.compactFormat(bytesPerSecond: uploadBytesPerSecond)
    }

    func start() {
        guard timerCancellable == nil else { return }

        refresh()

        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    private func refresh() {
        networkName = wifiProvider.currentSSID()

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
        let receivedDelta = snapshot.receivedBytes >= lastSnapshot.receivedBytes
            ? snapshot.receivedBytes - lastSnapshot.receivedBytes
            : 0
        let sentDelta = snapshot.sentBytes >= lastSnapshot.sentBytes
            ? snapshot.sentBytes - lastSnapshot.sentBytes
            : 0

        downloadBytesPerSecond = UInt64(Double(receivedDelta) / interval)
        uploadBytesPerSecond = UInt64(Double(sentDelta) / interval)
    }

    private static func format(bytesPerSecond: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    private static func compactFormat(bytesPerSecond: UInt64) -> String {
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
}
