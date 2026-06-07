import SwiftUI
import AppKit

/// Shared brand color tokens for all Imperator apps. See section 2.6 of
/// the Imperator BrandBook for the full token set and usage rules.
enum AppColors {
    // SwiftUI tokens
    static let brand = Color(red: 0xa0/255.0, green: 0x18/255.0, blue: 0x18/255.0)
    static let brandFaded = brand.opacity(0.25)
    static let accent = Color(red: 0.43, green: 0.05, blue: 0.05)
    static let badgeRed = Color(red: 0xD9/255.0, green: 0x33/255.0, blue: 0x33/255.0)
    static let error = Color(red: 0.9, green: 0.3, blue: 0.3)

    // AppKit tokens — required for pure NSView code (panels, overlays)
    static let brandNS = NSColor(red: 0xa0/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
    static let backgroundNS = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
}
