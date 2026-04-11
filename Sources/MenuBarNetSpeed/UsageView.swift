import NetSpeedKit
import SwiftUI

struct UsageView: View {
    @ObservedObject var tracker: UsageTracker
    @ObservedObject var settings: SettingsManager
    @State private var selectedPeriod: UsageTracker.TimePeriod = .today

    var body: some View {
        VStack(spacing: 0) {
            // Period selector
            periodPicker
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            // Totals cards
            totalsSection
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            // Bar chart
            chartSection
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            // Peak speeds
            peakSection
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(width: 300)
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(UsageTracker.TimePeriod.allCases) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 11, weight: selectedPeriod == period ? .semibold : .regular))
                        .foregroundStyle(selectedPeriod == period ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if selectedPeriod == period {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
    }

    // MARK: - Totals

    private var totalsSection: some View {
        let totals = tracker.totals(for: selectedPeriod)
        return HStack(spacing: 10) {
            usageCard(
                title: "Downloaded",
                bytes: totals.download,
                systemImage: "arrow.down.circle.fill",
                tint: .blue
            )
            usageCard(
                title: "Uploaded",
                bytes: totals.upload,
                systemImage: "arrow.up.circle.fill",
                tint: .purple
            )
        }
    }

    private func usageCard(title: String, bytes: UInt64, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(SpeedFormatter.formatByteCount(bytes))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.1), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                legendDot(color: .blue, label: "Down")
                legendDot(color: .purple, label: "Up")
                Spacer()
                Text(chartSubtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            let bars = chartData
            if bars.isEmpty {
                Text("No data yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                UsageBarChart(bars: bars, period: selectedPeriod)
                    .frame(height: 80)
            }
        }
    }

    private var chartSubtitle: String {
        switch selectedPeriod {
        case .today: return "Hourly breakdown"
        case .week: return "Daily breakdown"
        case .month: return "Daily breakdown"
        }
    }

    private var chartData: [UsageBar] {
        switch selectedPeriod {
        case .today:
            return tracker.todayHourlyBreakdown().map { item in
                UsageBar(
                    label: SpeedFormatter.formatHour(item.hour),
                    download: item.download,
                    upload: item.upload
                )
            }
        case .week:
            return tracker.dailyBreakdown(days: 7).map { item in
                UsageBar(
                    label: SpeedFormatter.formatWeekday(item.day),
                    download: item.download,
                    upload: item.upload
                )
            }
        case .month:
            return tracker.dailyBreakdown(days: 30).map { item in
                UsageBar(
                    label: SpeedFormatter.formatShortDate(item.day),
                    download: item.download,
                    upload: item.upload
                )
            }
        }
    }

    // MARK: - Peaks

    private var peakSection: some View {
        let totals = tracker.totals(for: selectedPeriod)
        let usesBits = settings.useBitsPerSecond
        return HStack {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue.opacity(0.7))
                Text("↓ \(SpeedFormatter.format(bytesPerSecond: totals.peakDown, asBits: usesBits))")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
            }

            Spacer()

            Text("Peak Speeds")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            Spacer()

            HStack(spacing: 4) {
                Text("↑ \(SpeedFormatter.format(bytesPerSecond: totals.peakUp, asBits: usesBits))")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple.opacity(0.7))
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bar Chart

struct UsageBar: Identifiable {
    let id = UUID()
    let label: String
    let download: UInt64
    let upload: UInt64

    var total: UInt64 { download + upload }
}

struct UsageBarChart: View {
    let bars: [UsageBar]
    let period: UsageTracker.TimePeriod

    var body: some View {
        let maxVal = max(bars.map(\.total).max() ?? 1, 1)

        GeometryReader { geo in
            let barWidth = max((geo.size.width - CGFloat(bars.count - 1) * 2) / CGFloat(bars.count), 4)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bars) { bar in
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)

                        // Upload (top, purple)
                        let uploadH = barHeight(bar.upload, maxVal: maxVal, totalHeight: geo.size.height - 14)
                        if uploadH > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.purple.opacity(0.6))
                                .frame(width: barWidth, height: uploadH)
                        }

                        // Download (bottom, blue)
                        let downloadH = barHeight(bar.download, maxVal: maxVal, totalHeight: geo.size.height - 14)
                        if downloadH > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: barWidth, height: downloadH)
                        }

                        // Label — only show some to avoid crowding
                        if shouldShowLabel(bar) {
                            Text(bar.label)
                                .font(.system(size: 7))
                                .foregroundStyle(.quaternary)
                                .lineLimit(1)
                        } else {
                            Text("")
                                .font(.system(size: 7))
                        }
                    }
                }
            }
        }
    }

    private func barHeight(_ value: UInt64, maxVal: UInt64, totalHeight: CGFloat) -> CGFloat {
        guard maxVal > 0, value > 0 else { return 0 }
        return max(CGFloat(Double(value) / Double(maxVal)) * totalHeight, 2)
    }

    private func shouldShowLabel(_ bar: UsageBar) -> Bool {
        guard let idx = bars.firstIndex(where: { $0.id == bar.id }) else { return false }
        switch period {
        case .today:
            // Show every 3rd hour label
            return idx % 3 == 0
        case .week:
            return true
        case .month:
            // Show every 5th day label
            return idx % 5 == 0 || idx == bars.count - 1
        }
    }
}
