import SwiftUI

struct SparklineView: View {
    let downloadSamples: [UInt64]
    let uploadSamples: [UInt64]
    let capacity: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Grid lines
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    Divider().opacity(0.3)
                    Spacer()
                }
                Divider().opacity(0.3)
            }

            sparklinePath(for: uploadSamples, color: .purple)
            sparklinePath(for: downloadSamples, color: .blue)
        }
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func sparklinePath(for samples: [UInt64], color: Color) -> some View {
        let allMax = max(
            downloadSamples.max() ?? 0,
            uploadSamples.max() ?? 0,
            1024 // minimum scale: 1 KB/s
        )

        return GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let stepX = samples.count > 1 ? width / CGFloat(capacity - 1) : width
            let maxVal = CGFloat(allMax)

            ZStack {
                // Filled area
                Path { path in
                    guard !samples.isEmpty else { return }
                    let startX = width - stepX * CGFloat(samples.count - 1)
                    path.move(to: CGPoint(x: startX, y: height))
                    for (i, sample) in samples.enumerated() {
                        let x = startX + stepX * CGFloat(i)
                        let y = height - (CGFloat(sample) / maxVal) * height
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Stroke line
                Path { path in
                    guard !samples.isEmpty else { return }
                    let startX = width - stepX * CGFloat(samples.count - 1)
                    path.move(to: CGPoint(
                        x: startX,
                        y: height - (CGFloat(samples[0]) / maxVal) * height
                    ))
                    for (i, sample) in samples.enumerated().dropFirst() {
                        let x = startX + stepX * CGFloat(i)
                        let y = height - (CGFloat(sample) / maxVal) * height
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(color.opacity(0.7), lineWidth: 1.2)
            }
        }
    }
}
