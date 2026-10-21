import SwiftUI

/// Lucide `folder`, the outline tab-folder. Drawn from Lucide's 24-unit path
/// rather than using `folder.fill`, whose solid body reads much heavier than the
/// other glyphs on a sidebar row.
///
/// Stroke-only, so it takes `foregroundStyle` from the row like any SF Symbol.
struct FolderGlyph: View {
    var size: CGFloat = 14

    var body: some View {
        FolderShape()
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// Lucide `lucide-folder` path, scaled from its 24x24 viewBox to whatever rect
/// it is handed.
private struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        let r = 2 * s

        var path = Path()
        // M20 20 a2 2 0 0 0 2-2 V8 a2 2 0 0 0-2-2 h-7.9
        path.move(to: p(20, 20))
        path.addArc(tangent1End: p(22, 20), tangent2End: p(22, 18), radius: r)
        path.addLine(to: p(22, 8))
        path.addArc(tangent1End: p(22, 6), tangent2End: p(20, 6), radius: r)
        path.addLine(to: p(12.1, 6))
        // a2 2 0 0 1-1.69-.9 L9.6 3.9 A2 2 0 0 0 7.93 3 H4
        path.addArc(tangent1End: p(10.41, 5.1), tangent2End: p(9.6, 3.9), radius: r)
        path.addLine(to: p(9.6, 3.9))
        path.addArc(tangent1End: p(7.93, 3), tangent2End: p(4, 3), radius: r)
        path.addLine(to: p(4, 3))
        // a2 2 0 0 0-2 2 v13 a2 2 0 0 0 2 2 Z
        path.addArc(tangent1End: p(2, 3), tangent2End: p(2, 5), radius: r)
        path.addLine(to: p(2, 18))
        path.addArc(tangent1End: p(2, 20), tangent2End: p(4, 20), radius: r)
        path.closeSubpath()
        return path
    }
}
