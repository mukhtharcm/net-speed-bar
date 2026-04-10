import Foundation

struct TrafficSnapshot {
    let timestamp: Date
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let interfaceNames: [String]
}

struct NetworkTrafficReader {
    func readSnapshot() -> TrafficSnapshot? {
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacePointer) == 0, let firstAddress = interfacePointer else {
            return nil
        }

        defer {
            freeifaddrs(interfacePointer)
        }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var names: [String] = []

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            guard isUp, isRunning, !isLoopback else { continue }
            guard let data = pointer.pointee.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else {
                continue
            }

            let name = String(cString: pointer.pointee.ifa_name)
            guard Self.isPhysicalInterface(name) else { continue }

            receivedBytes += UInt64(data.ifi_ibytes)
            sentBytes += UInt64(data.ifi_obytes)

            if !names.contains(name) {
                names.append(name)
            }
        }

        names.sort()
        return TrafficSnapshot(
            timestamp: Date(),
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            interfaceNames: names
        )
    }

    private static func isPhysicalInterface(_ name: String) -> Bool {
        let prefixes = ["en", "bridge", "pdp_ip", "utun", "llw"]
        return prefixes.contains { name.hasPrefix($0) }
    }
}
