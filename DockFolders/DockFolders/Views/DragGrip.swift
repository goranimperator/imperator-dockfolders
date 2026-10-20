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
struct DragGrip: View {
    /// At rest the grip sits at the weight of the secondary text beside it, so a
    /// row reads as one line rather than a control with a label after it.
    /// Hovering the row brings it up to the weight of the row's other buttons.
    var hovered: Bool

    private static let dot: CGFloat = 3.5
    private static let columnGap: CGFloat = 1.5
    private static let rowGap: CGFloat = 2.5

    var body: some View {
        VStack(spacing: Self.rowGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: Self.columnGap) {
                    Circle().frame(width: Self.dot, height: Self.dot)
                    Circle().frame(width: Self.dot, height: Self.dot)
                }
            }
        }
        // Keep this animation on the grip, never on an enclosing Button. A
        // .animation(_:value:) on the button animates its whole label, image
        // included, and SwiftUI cross-fades the image on every hover: it reads
        // as the icon blinking.
        .foregroundStyle(hovered ? AnyShapeStyle(Color.gray) : AnyShapeStyle(.tertiary))
        .animation(.easeInOut(duration: 0.3), value: hovered)
    }
}
