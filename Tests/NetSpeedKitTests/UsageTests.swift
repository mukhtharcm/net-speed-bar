import Foundation
import Testing

@testable import NetSpeedKit

// MARK: - HourlyUsageRecord

@Suite("HourlyUsageRecord")
struct HourlyUsageRecordTests {
    @Test("Default values are zero")
    func defaults() {
        let record = HourlyUsageRecord(hourStart: Date())
        #expect(record.downloadBytes == 0)
        #expect(record.uploadBytes == 0)
        #expect(record.peakDownloadBytesPerSec == 0)
        #expect(record.peakUploadBytesPerSec == 0)
        #expect(record.sampleCount == 0)
    }

    @Test("addSample accumulates bytes and tracks peaks")
    func addSample() {
        var record = HourlyUsageRecord(hourStart: Date())

        record.addSample(downloadDelta: 1000, uploadDelta: 500, downloadBytesPerSec: 100, uploadBytesPerSec: 50)
        #expect(record.downloadBytes == 1000)
        #expect(record.uploadBytes == 500)
        #expect(record.peakDownloadBytesPerSec == 100)
        #expect(record.peakUploadBytesPerSec == 50)
        #expect(record.sampleCount == 1)

        record.addSample(downloadDelta: 2000, uploadDelta: 800, downloadBytesPerSec: 80, uploadBytesPerSec: 90)
        #expect(record.downloadBytes == 3000)
        #expect(record.uploadBytes == 1300)
        #expect(record.peakDownloadBytesPerSec == 100)  // stays at first peak
        #expect(record.peakUploadBytesPerSec == 90)     // new peak
        #expect(record.sampleCount == 2)
    }

    @Test("Codable round-trip preserves data")
    func codable() throws {
        let now = Date()
        var record = HourlyUsageRecord(hourStart: now)
        record.addSample(downloadDelta: 5000, uploadDelta: 3000, downloadBytesPerSec: 500, uploadBytesPerSec: 300)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HourlyUsageRecord.self, from: data)

        #expect(decoded.downloadBytes == 5000)
        #expect(decoded.uploadBytes == 3000)
        #expect(decoded.peakDownloadBytesPerSec == 500)
        #expect(decoded.sampleCount == 1)
    }
}

// MARK: - DailyUsageRecord

@Suite("DailyUsageRecord")
struct DailyUsageRecordTests {
    @Test("Aggregate from hourly records")
    func aggregate() {
        let base = Calendar.current.startOfDay(for: Date())
        let records = [
            HourlyUsageRecord(hourStart: base, downloadBytes: 1000, uploadBytes: 500, peakDownloadBytesPerSec: 100, peakUploadBytesPerSec: 50, sampleCount: 10),
            HourlyUsageRecord(hourStart: base.addingTimeInterval(3600), downloadBytes: 2000, uploadBytes: 800, peakDownloadBytesPerSec: 200, peakUploadBytesPerSec: 80, sampleCount: 20),
            HourlyUsageRecord(hourStart: base.addingTimeInterval(7200), downloadBytes: 500, uploadBytes: 300, peakDownloadBytesPerSec: 50, peakUploadBytesPerSec: 30, sampleCount: 5),
        ]

        let daily = DailyUsageRecord.aggregate(from: records)
        #expect(daily != nil)
        #expect(daily!.downloadBytes == 3500)
        #expect(daily!.uploadBytes == 1600)
        #expect(daily!.peakDownloadBytesPerSec == 200)
        #expect(daily!.peakUploadBytesPerSec == 80)
    }

    @Test("Aggregate from empty returns nil")
    func aggregateEmpty() {
        let daily = DailyUsageRecord.aggregate(from: [])
        #expect(daily == nil)
    }
}

// MARK: - Date.startOfHour

@Suite("Date.startOfHour")
struct DateStartOfHourTests {
    @Test("Zeroes minutes and seconds")
    func zeroesMinutes() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 11
        comps.hour = 14
        comps.minute = 37
        comps.second = 42
        let date = Calendar.current.date(from: comps)!
        let hourStart = date.startOfHour()

        let result = Calendar.current.dateComponents([.minute, .second], from: hourStart)
        #expect(result.minute == 0)
        #expect(result.second == 0)
    }

    @Test("Already at hour start stays the same")
    func alreadyAtHour() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 11
        comps.hour = 14
        comps.minute = 0
        comps.second = 0
        let date = Calendar.current.date(from: comps)!
        let hourStart = date.startOfHour()
        #expect(date == hourStart)
    }
}

// MARK: - UsageStore

@Suite("UsageStore")
struct UsageStoreTests {
    private func makeTempStore() -> (UsageStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (UsageStore(directory: dir), dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Save and load round-trip")
    func saveLoad() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        var data = UsageData()
        data.hourlyRecords.append(HourlyUsageRecord(hourStart: Date(), downloadBytes: 1234, uploadBytes: 567))
        store.save(data)

        let loaded = store.load()
        #expect(loaded.hourlyRecords.count == 1)
        #expect(loaded.hourlyRecords[0].downloadBytes == 1234)
    }

    @Test("Load from non-existent file returns empty data")
    func loadEmpty() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = UsageStore(directory: dir)
        let data = store.load()
        #expect(data.hourlyRecords.isEmpty)
        #expect(data.dailyRecords.isEmpty)
    }

    @Test("Pruning removes old hourly records")
    func pruneHourly() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -31, to: now)!
        let recent = Calendar.current.date(byAdding: .day, value: -1, to: now)!

        var data = UsageData()
        data.hourlyRecords = [
            HourlyUsageRecord(hourStart: old, downloadBytes: 100),
            HourlyUsageRecord(hourStart: recent, downloadBytes: 200),
        ]

        let pruned = store.pruned(data, now: now)
        #expect(pruned.hourlyRecords.count == 1)
        #expect(pruned.hourlyRecords[0].downloadBytes == 200)
    }

    @Test("Pruning removes old daily records beyond 365 days")
    func pruneDaily() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -400, to: now)!
        let recent = Calendar.current.date(byAdding: .day, value: -100, to: now)!

        var data = UsageData()
        data.dailyRecords = [
            DailyUsageRecord(dayStart: old, downloadBytes: 100),
            DailyUsageRecord(dayStart: recent, downloadBytes: 200),
        ]

        let pruned = store.pruned(data, now: now)
        #expect(pruned.dailyRecords.count == 1)
        #expect(pruned.dailyRecords[0].downloadBytes == 200)
    }

    @Test("Roll up creates daily records from past hourly records")
    func rollUp() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!

        var data = UsageData()
        data.hourlyRecords = [
            HourlyUsageRecord(hourStart: yesterday, downloadBytes: 1000, uploadBytes: 500, peakDownloadBytesPerSec: 100, peakUploadBytesPerSec: 50),
            HourlyUsageRecord(hourStart: yesterday.addingTimeInterval(3600), downloadBytes: 2000, uploadBytes: 800, peakDownloadBytesPerSec: 200, peakUploadBytesPerSec: 80),
        ]

        let rolled = store.rolledUp(data, now: now)
        #expect(rolled.dailyRecords.count == 1)
        #expect(rolled.dailyRecords[0].downloadBytes == 3000)
        #expect(rolled.dailyRecords[0].uploadBytes == 1300)
        #expect(rolled.dailyRecords[0].peakDownloadBytesPerSec == 200)
    }

    @Test("Roll up does not create daily record for today")
    func rollUpSkipsToday() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let now = Date()
        let hourStart = now.startOfHour()

        var data = UsageData()
        data.hourlyRecords = [
            HourlyUsageRecord(hourStart: hourStart, downloadBytes: 5000),
        ]

        let rolled = store.rolledUp(data, now: now)
        #expect(rolled.dailyRecords.isEmpty)
    }

    @Test("Aggregate totals combines daily and hourly")
    func aggregateTotals() {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        let data = UsageData(
            hourlyRecords: [
                HourlyUsageRecord(hourStart: todayStart, downloadBytes: 500, uploadBytes: 200, peakDownloadBytesPerSec: 50, peakUploadBytesPerSec: 20),
            ],
            dailyRecords: [
                DailyUsageRecord(dayStart: yesterdayStart, downloadBytes: 10000, uploadBytes: 5000, peakDownloadBytesPerSec: 1000, peakUploadBytesPerSec: 500),
            ]
        )

        let totals = UsageStore.aggregateTotals(from: yesterdayStart, to: now, in: data, now: now)
        #expect(totals.downloadBytes == 10500)
        #expect(totals.uploadBytes == 5200)
        #expect(totals.peakDown == 1000)
        #expect(totals.peakUp == 500)
    }

    @Test("Hourly records query filters by date")
    func hourlyRecordsForDate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let data = UsageData(hourlyRecords: [
            HourlyUsageRecord(hourStart: yesterday, downloadBytes: 100),
            HourlyUsageRecord(hourStart: today, downloadBytes: 200),
            HourlyUsageRecord(hourStart: today.addingTimeInterval(3600), downloadBytes: 300),
        ])

        let todayRecords = UsageStore.hourlyRecords(for: Date(), in: data)
        #expect(todayRecords.count == 2)
        #expect(todayRecords[0].downloadBytes == 200)
        #expect(todayRecords[1].downloadBytes == 300)
    }
}

// MARK: - SpeedFormatter Date Formatting

@Suite("SpeedFormatter — Date Formatting")
struct SpeedFormatterDateFormattingTests {
    @Test("formatHour returns short hour string")
    func formatHour() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 11
        comps.hour = 14
        let date = Calendar.current.date(from: comps)!
        let result = SpeedFormatter.formatHour(date)
        #expect(result.contains("2") || result.contains("PM") || result.contains("pm"))
    }

    @Test("formatShortDate returns month and day")
    func formatShortDate() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 11
        let date = Calendar.current.date(from: comps)!
        let result = SpeedFormatter.formatShortDate(date)
        #expect(result.contains("Apr"))
        #expect(result.contains("11"))
    }

    @Test("formatWeekday returns short day name")
    func formatWeekday() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 11  // Saturday
        let date = Calendar.current.date(from: comps)!
        let result = SpeedFormatter.formatWeekday(date)
        #expect(result.count <= 3)
        #expect(!result.isEmpty)
    }
}
