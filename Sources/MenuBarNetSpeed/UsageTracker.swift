import Combine
import Foundation
import NetSpeedKit

/// Tracks network usage over time, persisting hourly and daily records.
/// Accumulates deltas fed from the ViewModel and flushes periodically.
@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    /// How often to write data to disk (seconds)
    private static let flushInterval: TimeInterval = 300  // 5 minutes

    @Published private(set) var usageData: UsageData = UsageData()

    private let store: UsageStore
    private var flushTimer: Timer?
    private var currentHourStart: Date

    init(store: UsageStore = UsageStore()) {
        self.store = store
        self.currentHourStart = Date().startOfHour()
        self.usageData = store.load()
        pruneAndRollUp()
        ensureCurrentHourBucket()
        startFlushTimer()
    }

    // MARK: - Public API

    /// Called by ViewModel on every refresh cycle with the deltas for this tick.
    func recordSample(
        downloadDelta: UInt64,
        uploadDelta: UInt64,
        downloadBytesPerSec: UInt64,
        uploadBytesPerSec: UInt64
    ) {
        let now = Date()
        let hourStart = now.startOfHour()

        // Hour rolled over — start a new bucket
        if hourStart != currentHourStart {
            currentHourStart = hourStart
            pruneAndRollUp()
            ensureCurrentHourBucket()
        }

        // Find or create the current hour bucket
        if let idx = usageData.hourlyRecords.firstIndex(where: { $0.hourStart == currentHourStart }) {
            usageData.hourlyRecords[idx].addSample(
                downloadDelta: downloadDelta,
                uploadDelta: uploadDelta,
                downloadBytesPerSec: downloadBytesPerSec,
                uploadBytesPerSec: uploadBytesPerSec
            )
        }
    }

    /// Flush data to disk immediately (call on app quit).
    func flush() {
        store.save(usageData)
    }

    // MARK: - Query Helpers

    enum TimePeriod: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "7 Days"
        case month = "30 Days"

        var id: String { rawValue }
    }

    func totals(for period: TimePeriod) -> (download: UInt64, upload: UInt64, peakDown: UInt64, peakUp: UInt64) {
        let now = Date()
        let calendar = Calendar.current
        let startDate: Date
        switch period {
        case .today:
            startDate = calendar.startOfDay(for: now)
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        case .month:
            startDate = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now)) ?? now
        }
        let result = UsageStore.aggregateTotals(from: startDate, to: now, in: usageData, now: now)
        return (result.downloadBytes, result.uploadBytes, result.peakDown, result.peakUp)
    }

    /// Hourly breakdown for today (for the bar chart).
    func todayHourlyBreakdown() -> [(hour: Date, download: UInt64, upload: UInt64)] {
        let records = UsageStore.hourlyRecords(for: Date(), in: usageData)
        return records.map { ($0.hourStart, $0.downloadBytes, $0.uploadBytes) }
    }

    /// Daily breakdown for the last N days (for the bar chart).
    func dailyBreakdown(days: Int) -> [(day: Date, download: UInt64, upload: UInt64)] {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? now

        // Past complete days from daily records
        var result: [(day: Date, download: UInt64, upload: UInt64)] = []
        let dailies = UsageStore.dailyRecords(from: startDate, to: now, in: usageData)
        for record in dailies {
            result.append((record.dayStart, record.downloadBytes, record.uploadBytes))
        }

        // Today from hourly records
        let todayHourly = UsageStore.hourlyRecords(for: now, in: usageData)
        if !todayHourly.isEmpty {
            let todayDown = todayHourly.reduce(0 as UInt64) { $0 + $1.downloadBytes }
            let todayUp = todayHourly.reduce(0 as UInt64) { $0 + $1.uploadBytes }
            result.append((todayStart, todayDown, todayUp))
        }

        return result.sorted { $0.day < $1.day }
    }

    // MARK: - Internal

    private func ensureCurrentHourBucket() {
        if !usageData.hourlyRecords.contains(where: { $0.hourStart == currentHourStart }) {
            usageData.hourlyRecords.append(HourlyUsageRecord(hourStart: currentHourStart))
        }
    }

    private func pruneAndRollUp() {
        usageData = store.rolledUp(usageData)
        usageData = store.pruned(usageData)
    }

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
    }
}
