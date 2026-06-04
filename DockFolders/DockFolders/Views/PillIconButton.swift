import SwiftUI

/// Compact pill-shaped icon button used in the sidebar settings rows.
/// Sized to match the macOS toggle switch on the row above (30×14).
struct PillIconButton: View {
    let systemImage: String
    let backgroundColor: Color
    let iconColor: Color
    var rotation: Double = 0
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(backgroundColor)
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(iconColor)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 29, height: 14)
            .opacity(hovered ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .offset(x: -1)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.1)) {
                hovered = h
            }
        }
    }
}
