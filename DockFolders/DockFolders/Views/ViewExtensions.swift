import SwiftUI
import AppKit

/// Cursor + tap-target helpers shared across Imperator apps.
/// See BrandBook section 2.7.
extension View {
    /// Push the given cursor while the pointer is inside this view. Pass nil
    /// for no cursor, for instance over a row whose rename field is open.
    ///
    /// Departs from BrandBook 2.7's plain onHover push/pop, which leaked: a view
    /// that went away under the pointer (a popup closing on a click, a row
    /// renamed) never got its hover-exit, so its cursor stayed pushed and the
    /// next pop elsewhere landed on it. This one remembers whether it pushed and
    /// pops on disappear as well.
    func cursor(_ cursor: NSCursor?) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }

    /// Make the entire bounding rect tappable, not just opaque subviews.
    func expandTapTarget() -> some View {
        contentShape(Rectangle())
    }
}

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor?
    @State private var pushed = false
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                inside = hovering
                update()
            }
            .onChange(of: cursor == nil) { _, _ in update() }
            .onDisappear {
                inside = false
                update()
            }
    }

    private func update() {
        let wanted = inside && cursor != nil
        if wanted && !pushed {
            cursor?.push()
            pushed = true
        } else if !wanted && pushed {
            NSCursor.pop()
            pushed = false
        }
    }
}
