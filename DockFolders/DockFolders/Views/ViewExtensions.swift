import SwiftUI
import AppKit

/// Cursor + tap-target helpers shared across Imperator apps.
/// See BrandBook section 2.7.
extension View {
    /// Push the given cursor while the pointer is inside this view.
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }

    /// Make the entire bounding rect tappable — not just opaque subviews.
    func expandTapTarget() -> some View {
        contentShape(Rectangle())
    }
}
