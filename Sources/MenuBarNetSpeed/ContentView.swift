import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: NetworkSpeedViewModel
    @ObservedObject var settings: SettingsManager
    @State private var showingSettings = false

    var body: some View {
        if showingSettings {
            SettingsView(settings: settings, isPresented: $showingSettings) {
                viewModel.requestNotificationPermission()
            }
        } else {
            mainContent
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            if settings.showNetworkName {
                headerSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                speedCard(
                    title: "Download",
                    value: viewModel.downloadSpeedText,
                    peak: viewModel.peakDownloadText,
                    systemImage: "arrow.down.circle.fill",
                    tint: .blue
                )
                speedCard(
                    title: "Upload",
                    value: viewModel.uploadSpeedText,
                    peak: viewModel.peakUploadText,
                    systemImage: "arrow.up.circle.fill",
                    tint: .purple
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, settings.showNetworkName ? 0 : 16)
            .padding(.bottom, 14)

            // Sparkline
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    legendDot(color: .blue, label: "Down")
                    legendDot(color: .purple, label: "Up")
                    Spacer()
                    Text("Last 60 samples")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }

                SparklineView(
                    downloadSamples: viewModel.downloadHistory,
                    uploadSamples: viewModel.uploadHistory,
                    capacity: 60
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Session totals
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue.opacity(0.7))
                    Text(viewModel.totalDownloadedText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }

                Spacer()

                Text("Session Total")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)

                Spacer()

                HStack(spacing: 4) {
                    Text(viewModel.totalUploadedText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            footerSection
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(width: 300)
        .onAppear {
            viewModel.setPopoverVisible(true)
            viewModel.start()
        }
        .onDisappear {
            viewModel.setPopoverVisible(false)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        let conn = viewModel.connectionType
        let isConnected = viewModel.showsConnectedState
        let iconTint: Color = {
            switch conn {
            case .wifi: return .green
            case .ethernet: return .blue
            case .vpn: return .orange
            case .cellular: return .purple
            case .other: return .teal
            case .none: return .secondary
            }
        }()

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(isConnected ? 0.15 : 0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: conn.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(viewModel.networkDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    // Show VPN badge when active alongside a physical connection
                    if viewModel.isVPNActive && conn != .vpn {
                        Text("VPN")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.orange))
                    }
                }

                Text(viewModel.interfaceSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - Speed Card

    private func speedCard(title: String, value: String, peak: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                Text("Peak \(peak)")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)
            .monospacedDigit()
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)

            Text(refreshLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .accessibilityLabel("Quit application")
        }
    }

    private var refreshLabel: String {
        let interval = settings.refreshInterval
        if interval == 1 {
            return "Live · every second"
        }
        return "Live · every \(Int(interval))s"
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
