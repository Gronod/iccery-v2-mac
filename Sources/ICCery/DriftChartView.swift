import SwiftUI
import ICCeryCore

/// Minimal line chart for drift history without depending on the
/// `Charts` framework link. Renders avg/max series with shaded quality
/// bands.
struct DriftChartView: View {
    let records: [VerificationRecord]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .topLeading) {
                if let (_, _, _, maxV) = scales(in: height) {
                    // Quality bands — bottom (red, > 3.5) drawn first, then
                    // orange, yellow, green so the upper-most bands overlay.
                    band(from: 3.5, to: maxV, color: .red.opacity(0.12), height: height, maxValue: maxV)
                    band(from: 2.0, to: 3.5, color: .orange.opacity(0.12), height: height, maxValue: maxV)
                    band(from: 1.0, to: 2.0, color: .yellow.opacity(0.12), height: height, maxValue: maxV)
                    band(from: 0.0, to: 1.0, color: .green.opacity(0.12), height: height, maxValue: maxV)
                }

                if !records.isEmpty, let (minT, maxT, minV, maxV) = scales(in: height) {
                    // Average ΔE series
                    Path { path in
                        for (index, record) in records.enumerated() {
                            let pt = point(
                                for: record,
                                minTime: minT,
                                maxTime: maxT,
                                minValue: minV,
                                maxValue: maxV,
                                width: width,
                                height: height,
                                keyPath: \.avgDE
                            )
                            if index == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                    .accessibilityIdentifier("driftAvgSeries")

                    // Max ΔE series
                    Path { path in
                        for (index, record) in records.enumerated() {
                            let pt = point(
                                for: record,
                                minTime: minT,
                                maxTime: maxT,
                                minValue: minV,
                                maxValue: maxV,
                                width: width,
                                height: height,
                                keyPath: \.maxDE
                            )
                            if index == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(Color.orange, lineWidth: 2)
                    .accessibilityIdentifier("driftMaxSeries")
                } else {
                    Text("No data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func band(
        from lower: Double,
        to upper: Double,
        color: Color,
        height: CGFloat,
        maxValue: Double
    ) -> some View {
        let yTop = valueY(lower, minValue: 0, maxValue: maxValue, height: height)
        let yBottom = valueY(upper, minValue: 0, maxValue: maxValue, height: height)
        return color
            .frame(height: yBottom - yTop)
            .offset(y: yTop)
    }

    private func scales(in height: CGFloat) -> (Date, Date, Double, Double)? {
        guard let minT = records.first?.timestamp, let maxT = records.last?.timestamp else { return nil }
        let maxV = max(records.map { max($0.avgDE, $0.maxDE) }.max() ?? 5.0, 5.0)
        return (minT, maxT, 0.0, maxV)
    }

    private func point(
        for record: VerificationRecord,
        minTime: Date,
        maxTime: Date,
        minValue: Double,
        maxValue: Double,
        width: CGFloat,
        height: CGFloat,
        keyPath: KeyPath<VerificationRecord, Double>
    ) -> CGPoint {
        let timeSpan = max(1, maxTime.timeIntervalSince(minTime))
        let x = width * CGFloat(record.timestamp.timeIntervalSince(minTime) / timeSpan)
        let y = valueY(record[keyPath: keyPath], minValue: minValue, maxValue: maxValue, height: height)
        return CGPoint(x: x, y: y)
    }

    private func valueY(_ value: Double, minValue: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        let valueSpan = max(1, maxValue - minValue)
        return height - height * CGFloat((value - minValue) / valueSpan)
    }
}
