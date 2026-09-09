import SwiftUI
import ICCeryCore

private extension DisplayRGB {
    var color: Color {
        Color(red: r, green: g, blue: b)
    }
}

/// One swatch in the live grid, with a 135° intended/measured diagonal split.
struct SwatchPatchView: View {
    let swatch: Swatch

    private var indicatorColor: Color {
        switch swatch.classification {
        case .good: return .green
        case .warning: return .yellow
        case .bad: return .red
        }
    }

    var body: some View {
        ZStack {
            // Background: measured
            swatch.measured.color
                .clipShape(DiagonalClip(side: .bottomRight))

            // Foreground: intended
            swatch.intended.color
                .clipShape(DiagonalClip(side: .topLeft))

            // Classification dot
            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)
                .offset(x: 6, y: 6)
        }
        .frame(width: 32, height: 32)
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityIdentifier("swatch-\(swatch.rowId)\(swatch.loc)")
        .accessibilityLabel("\(swatch.loc) intended \(String(format: "%.0f", swatch.intended.r * 255)), measured \(String(format: "%.0f", swatch.measured.r * 255))")
    }
}

/// 135° diagonal clipping: top-left or bottom-right triangle.
///
/// A 135° line from the top-right corner to the bottom-left corner gives
/// top-left and bottom-right triangles.
private enum DiagonalSide {
    case topLeft
    case bottomRight
}

private struct DiagonalClip: Shape {
    let side: DiagonalSide

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch side {
        case .topLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .bottomRight:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
