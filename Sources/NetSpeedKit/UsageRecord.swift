import Foundation

/// A single hourly bucket of network usage.
public struct HourlyUsageRecord: Codable, Sendable, Equatable {
    /// Start of the hour (minute/second zeroed)
    public var hourStart: Date
    public var downloadBytes: UInt64
    public var uploadBytes: UInt64
    public var peakDownloadBytesPerSec: UInt64
    public var peakUploadBytesPerSec: UInt64
    /// Number of refresh samples that contributed to this bucket
    public var sampleCount: Int

    public init(
        hourStart: Date,
        downloadBytes: UInt64 = 0,
        uploadBytes: UInt64 = 0,
        peakDownloadBytesPerSec: UInt64 = 0,
        peakUploadBytesPerSec: UInt64 = 0,
        sampleCount: Int = 0
    ) {
        self.hourStart = hourStart
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
        self.peakDownloadBytesPerSec = peakDownloadBytesPerSec
        self.peakUploadBytesPerSec = peakUploadBytesPerSec
        self.sampleCount = sampleCount
    }

    /// Add a speed sample to this bucket.
    public mutating func addSample(
        downloadDelta: UInt64,
        uploadDelta: UInt64,
        downloadBytesPerSec: UInt64,
        uploadBytesPerSec: UInt64
    ) {
        downloadBytes += downloadDelta
        uploadBytes += uploadDelta
        peakDownloadBytesPerSec = max(peakDownloadBytesPerSec, downloadBytesPerSec)
        peakUploadBytesPerSec = max(peakUploadBytesPerSec, uploadBytesPerSec)
        sampleCount += 1
    }
}

/// A daily summary aggregated from hourly records.
public struct DailyUsageRecord: Codable, Sendable, Equatable {
    /// Start of the day (hour/minute/second zeroed)
    public var dayStart: Date
    public var downloadBytes: UInt64
    public var uploadBytes: UInt64
    public var peakDownloadBytesPerSec: UInt64
    public var peakUploadBytesPerSec: UInt64

    public init(
        dayStart: Date,
        downloadBytes: UInt64 = 0,
        uploadBytes: UInt64 = 0,
        peakDownloadBytesPerSec: UInt64 = 0,
        peakUploadBytesPerSec: UInt64 = 0
    ) {
        self.dayStart = dayStart
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
        self.peakDownloadBytesPerSec = peakDownloadBytesPerSec
        self.peakUploadBytesPerSec = peakUploadBytesPerSec
    }

    /// Build a daily summary from hourly records.
    public static func aggregate(from hourlyRecords: [HourlyUsageRecord]) -> DailyUsageRecord? {
        guard let first = hourlyRecords.first else { return nil }
        let dayStart = Calendar.current.startOfDay(for: first.hourStart)
        return DailyUsageRecord(
            dayStart: dayStart,
            downloadBytes: hourlyRecords.reduce(0) { $0 + $1.downloadBytes },
            uploadBytes: hourlyRecords.reduce(0) { $0 + $1.uploadBytes },
            peakDownloadBytesPerSec: hourlyRecords.map(\.peakDownloadBytesPerSec).max() ?? 0,
            peakUploadBytesPerSec: hourlyRecords.map(\.peakUploadBytesPerSec).max() ?? 0
        )
    }
}

/// Top-level container for persisted usage data.
public struct UsageData: Codable, Sendable {
    public var hourlyRecords: [HourlyUsageRecord]
    public var dailyRecords: [DailyUsageRecord]

    public init(
        hourlyRecords: [HourlyUsageRecord] = [],
        dailyRecords: [DailyUsageRecord] = []
    ) {
        self.hourlyRecords = hourlyRecords
        self.dailyRecords = dailyRecords
    }
}

// MARK: - Calendar Helpers

extension Date {
    /// Returns the start of the hour for this date.
    public func startOfHour(calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: self)
        return calendar.date(from: comps) ?? self
    }
}
