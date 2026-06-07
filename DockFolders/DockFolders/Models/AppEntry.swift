import SwiftUI
import AppKit

struct AppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let localURL: URL
    let icon: NSImage

    private static var iconCache: [String: NSImage] = [:]

    static func clearIconCache() {
        iconCache.removeAll()
    }

    private static func cachedIcon(forFile path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        // BrandBook 22.2: resolve symlinks before reading the icon so Cryptex-
        // mounted apps return the correct appearance-aware artwork.
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let icon = NSWorkspace.shared.icon(forFile: resolved)
        iconCache[path] = icon
        return icon
    }

    init(url: URL) {
        self.url = url
        self.localURL = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.id = url.path
        self.icon = Self.cachedIcon(forFile: url.path)
    }

    init(localURL: URL, resolvedURL: URL) {
        self.localURL = localURL
        self.url = resolvedURL
        self.name = resolvedURL.deletingPathExtension().lastPathComponent
        self.id = resolvedURL.path
        self.icon = Self.cachedIcon(forFile: resolvedURL.path)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppEntry, rhs: AppEntry) -> Bool {
        lhs.id == rhs.id
    }
}
