import Foundation

enum AppearanceMode: String, CaseIterable {
    case system
    case dark

    var displayName: String {
        switch self {
        case .system: return "Follow system"
        case .dark: return "Always dark"
        }
    }
}
