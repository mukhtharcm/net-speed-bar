import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: NetworkSpeedViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.networkDisplayName)
                    .font(.headline)

                Text(viewModel.interfaceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                statBlock(title: "Download", value: viewModel.downloadSpeedText, systemImage: "arrow.down.circle.fill")
                statBlock(title: "Upload", value: viewModel.uploadSpeedText, systemImage: "arrow.up.circle.fill")
            }

            Divider()

            HStack {
                Text("Updates every second")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            viewModel.start()
        }
    }

    @ViewBuilder
    private func statBlock(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
