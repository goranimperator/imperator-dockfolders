import SwiftUI
import AppKit

struct SigilView: View {
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    private static let svgTemplate = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="-80 -80 160 160">
      <defs>
        <g id="unit">
          <path d="
            M 4.5 22.8
            L 4.5 64
            C 4.5 70, 10 69.41, 12 69.41
            A 118.58 118.58 0 0 0 58.51 54.56
            A 80 80 0 0 1 -58.51 54.56
            A 118.58 118.58 0 0 0 -12 69.41
            C -10 69.41, -4.5 70, -4.5 64
            L -4.5 22.8
            A 8 8 0 0 0 -8.65 15.79
            L 8.65 15.79
            A 8 8 0 0 0 4.5 22.8
            Z
          " />
        </g>
      </defs>
      <g fill="FILL_COLOR">
        <use href="#unit" />
        <use href="#unit" transform="rotate(120)" />
        <use href="#unit" transform="rotate(240)" />
        <path fill-rule="evenodd" d="
          M 18 0 A 18 18 0 1 0 -18 0 A 18 18 0 1 0 18 0 Z
          M 9 0 A 9 9 0 1 0 -9 0 A 9 9 0 1 0 9 0 Z
        " />
      </g>
    </svg>
    """

    private var nsImage: NSImage? {
        let fillColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let svg = Self.svgTemplate.replacingOccurrences(of: "FILL_COLOR", with: fillColor)
        guard let data = svg.data(using: .utf8) else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        if let image = nsImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}
