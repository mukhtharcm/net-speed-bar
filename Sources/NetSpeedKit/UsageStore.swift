import Foundation

/// Reads and writes usage data as JSON.
/// Thread-safe: all operations are synchronous and should be called from a known context.
public final class UsageStore: Sendable {
    /// Maximum days of hourly records to keep (30 days = 720 hours max)
    public static let hourlyRetentionDays = 30
    /// Maximum days of daily records to keep
    public static let dailyRetentionDays = 365

    private let fileURL: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? UsageStore.defaultDirectory
        self.fileURL = dir.appendingPathComponent("usage.json")
    }

    /// Default storage directory: ~/Library/Application Support/com.mukhtharcm.netspeedbar/
    public static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.mukhtharcm.netspeedbar")
    }

    // MARK: - Read / Write

    public func load() -> UsageData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return UsageData()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UsageData.self, from: data)
        } catch {
            return UsageData()
        }
    }

    public func save(_ usageData: UsageData) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(usageData)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent failure — don't crash the app for usage tracking
        }
    }

    // MARK: - Pruning

    /// Remove records older than retention limits. Returns the pruned data.
    public func pruned(_ data: UsageData, now: Date = Date()) -> UsageData {
        let calendar = Calendar.current
        let hourCutoff = calendar.date(byAdding: .day, value: -Self.hourlyRetentionDays, to: now) ?? now
        let dayCutoff = calendar.date(byAdding: .day, value: -Self.dailyRetentionDays, to: now) ?? now

        return UsageData(
            hourlyRecords: data.hourlyRecords.filter { $0.hourStart >= hourCutoff },
            dailyRecords: data.dailyRecords.filter { $0.dayStart >= dayCutoff }
        )
    }

    // MARK: - Roll Up

    /// Roll up completed hourly records into daily summaries.
    /// Keeps hourly records intact; only creates/updates daily records for past complete days.
    public func rolledUp(_ data: UsageData, now: Date = Date()) -> UsageData {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        var result = data

        // Group hourly records by day
        let byDay = Dictionary(grouping: data.hourlyRecords) { record in
            calendar.startOfDay(for: record.hourStart)
        }

        // Only roll up days that are fully complete (before today)
        for (dayStart, hourlyForDay) in byDay where dayStart < todayStart {
            guard let aggregate = DailyUsageRecord.aggregate(from: hourlyForDay) else { continue }

            if let idx = result.dailyRecords.firstIndex(where: { calendar.isDate($0.dayStart, inSameDayAs: dayStart) }) {
                // Update existing daily record
                result.dailyRecords[idx] = aggregate
            } else {
                result.dailyRecords.append(aggregate)
            }
        }

        // Sort daily records chronologically
        result.dailyRecords.sort { $0.dayStart < $1.dayStart }
        return result
    }

    // MARK: - Queries

    /// Get hourly records for a specific day.
    public static func hourlyRecords(for date: Date, in data: UsageData) -> [HourlyUsageRecord] {
        let calendar = Calendar.current
        return data.hourlyRecords
            .filter { calendar.isDate($0.hourStart, inSameDayAs: date) }
            .sorted { $0.hourStart < $1.hourStart }
    }

    /// Get daily records for a date range.
    public static func dailyRecords(from startDate: Date, to endDate: Date, in data: UsageData) -> [DailyUsageRecord] {
        data.dailyRecords
            .filter { $0.dayStart >= startDate && $0.dayStart <= endDate }
            .sorted { $0.dayStart < $1.dayStart }
    }

    /// Aggregate totals for a date range (combines hourly for today + daily for past days).
    public static func aggregateTotals(
        from startDate: Date,
        to endDate: Date,
        in data: UsageData,
        now: Date = Date()
    ) -> (downloadBytes: UInt64, uploadBytes: UInt64, peakDown: UInt64, peakUp: UInt64) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0
        var peakDown: UInt64 = 0
        var peakUp: UInt64 = 0

        // Past complete days: use daily records
        for record in data.dailyRecords where record.dayStart >= startDate && record.dayStart < todayStart && record.dayStart <= endDate {
            totalDown += record.downloadBytes
            totalUp += record.uploadBytes
            peakDown = max(peakDown, record.peakDownloadBytesPerSec)
            peakUp = max(peakUp, record.peakUploadBytesPerSec)
        }

        // Today (and any partial days in range): use hourly records
        for record in data.hourlyRecords where record.hourStart >= max(startDate, todayStart) && record.hourStart <= endDate {
            totalDown += record.downloadBytes
            totalUp += record.uploadBytes
            peakDown = max(peakDown, record.peakDownloadBytesPerSec)
            peakUp = max(peakUp, record.peakUploadBytesPerSec)
        }

        return (totalDown, totalUp, peakDown, peakUp)
    }
}
