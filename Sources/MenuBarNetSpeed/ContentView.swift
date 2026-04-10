import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: NetworkSpeedViewModel
    @ObservedObject var settings: SettingsManager
    @State private var showingSettings = false

    var body: some View {
        if showingSettings {
            SettingsView(settings: settings, isPresented: $showingSettings)
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
                    systemImage: "arrow.down.circle.fill",
                    tint: .blue
                )
                speedCard(
                    title: "Upload",
                    value: viewModel.uploadSpeedText,
                    systemImage: "arrow.up.circle.fill",
                    tint: .purple
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, settings.showNetworkName ? 0 : 16)
            .padding(.bottom, 14)

            footerSection
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(width: 300)
        .onAppear {
            viewModel.start()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(viewModel.networkName != nil ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: viewModel.networkName != nil ? "wifi" : "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(viewModel.networkName != nil ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.networkDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(viewModel.interfaceSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - Speed Card

    private func speedCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
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

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
    }

    private var refreshLabel: String {
        let interval = settings.refreshInterval
        if interval == 1 {
            return "Live · every second"
        }
        return "Live · every \(Int(interval))s"
    }
}
