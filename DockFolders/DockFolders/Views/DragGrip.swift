import SwiftUI

/// Lucide `grip-vertical`, two columns of three dots. The grip at the left of a
/// row you can drag to reorder.
///
/// The sizes are half-points, not the 3.33pt and 1.67pt that Lucide's 24-unit
/// box gives at 20pt. A fraction like that falls between device pixels, and each
/// dot rounds by where it happens to land, so they come out visibly unequal.
/// Half-points are exact at 2x: 7px dots, 3px between columns, 5px between rows.
///
/// Drawn rather than added to a Lucide icon set, which would put it in an icon
/// picker as a selectable icon.
///
/// Do not swap this for a stock symbol. `line.3.horizontal` and the other
/// hamburger glyphs run the full width of a column next to the row's folder
/// icon; this grip is 8.5pt wide.
///
/// Colour comes from the caller, so the grip follows the rest of the row (grey
/// at rest, white on a selected row) rather than fighting it with its own.
struct DragGrip: View {
    private static let dot: CGFloat = 3.5
    private static let columnGap: CGFloat = 1.5
    private static let rowGap: CGFloat = 2.5

    /// Three dot rows plus the two gaps between them: 15.5pt. Exposed so the
    /// glyph beside the grip can match its height exactly.
    static let height: CGFloat = dot * 3 + rowGap * 2

    var body: some View {
        VStack(spacing: Self.rowGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: Self.columnGap) {
                    Circle().frame(width: Self.dot, height: Self.dot)
                    Circle().frame(width: Self.dot, height: Self.dot)
                }
            }
        }
    }
}
