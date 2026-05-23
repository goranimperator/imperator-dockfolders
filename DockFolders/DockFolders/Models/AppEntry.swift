import SwiftUI
import AppKit

struct AppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let localURL: URL
    let icon: NSImage

    init(url: URL) {
        self.url = url
        self.localURL = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.id = url.path
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    init(localURL: URL, resolvedURL: URL) {
        self.localURL = localURL
        self.url = resolvedURL
        self.name = resolvedURL.deletingPathExtension().lastPathComponent
        self.id = resolvedURL.path
        self.icon = NSWorkspace.shared.icon(forFile: resolvedURL.path)
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
