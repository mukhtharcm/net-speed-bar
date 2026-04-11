import Foundation

/// Pure formatting functions for network speed and latency values.
/// Extracted for testability — no UI or state dependencies.
public enum SpeedFormatter {

    // MARK: - Speed Formatting

    // ByteCountFormatter isn't Sendable but we only mutate it during init.
    nonisolated(unsafe) private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    public static func format(bytesPerSecond: UInt64, asBits: Bool = false) -> String {
        if asBits {
            return formatBits(bytesPerSecond: bytesPerSecond)
        }
        return "\(byteCountFormatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    public static func formatBits(bytesPerSecond: UInt64) -> String {
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

    public static func compactFormat(bytesPerSecond: UInt64, asBits: Bool = false) -> String {
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

    public static func compactFormatBits(bytesPerSecond: UInt64) -> String {
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

    // MARK: - Byte Count

    public static func formatByteCount(_ bytes: UInt64) -> String {
        byteCountFormatter.string(fromByteCount: Int64(clamping: bytes))
    }

    // MARK: - Latency Formatting

    public static func formatLatency(_ ms: Double) -> String {
        if ms < 1 {
            return "<1 ms"
        } else if ms < 10 {
            return String(format: "%.1f ms", ms)
        } else {
            return "\(Int(ms.rounded())) ms"
        }
    }

    public static func compactLatency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        if ms < 1 { return "<1ms" }
        if ms < 10 { return String(format: "%.0fms", ms) }
        return "\(Int(ms.rounded()))ms"
    }

    // MARK: - Threshold Check

    /// Returns the direction name ("Download" or "Upload") if a threshold is exceeded, nil otherwise.
    public static func checkThreshold(
        downloadBytesPerSecond: UInt64,
        uploadBytesPerSecond: UInt64,
        thresholdMBps: Double
    ) -> (direction: String, speed: UInt64)? {
        let thresholdBytes = UInt64(thresholdMBps * 1024 * 1024)
        guard thresholdBytes > 0 else { return nil }

        if downloadBytesPerSecond > thresholdBytes {
            return ("Download", downloadBytesPerSecond)
        }
        if uploadBytesPerSecond > thresholdBytes {
            return ("Upload", uploadBytesPerSecond)
        }
        return nil
    }

    // MARK: - Date Formatting (for historical usage)

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"  // "2PM"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"  // "Apr 11"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"  // "Mon"
        return f
    }()

    /// Format an hour label like "2PM"
    public static func formatHour(_ date: Date) -> String {
        hourFormatter.string(from: date)
    }

    /// Format a short date like "Apr 11"
    public static func formatShortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    /// Format a weekday like "Mon"
    public static func formatWeekday(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }
}
