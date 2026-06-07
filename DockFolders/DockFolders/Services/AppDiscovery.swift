import Foundation
import AppKit

class AppDiscovery {
    static func installedApps() -> [URL] {
        let fm = FileManager.default
        var apps: [URL] = []

        var searchPaths = [
            "/Applications",
            "/System/Applications",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        // Include apps bundled inside Xcode (Icon Composer, Instruments, etc.)
        let xcodeApps = "/Applications/Xcode.app/Contents/Applications"
        if fm.fileExists(atPath: xcodeApps) {
            searchPaths.append(xcodeApps)
        }

        for dir in searchPaths {
            // BrandBook 22.1: string-based contentsOfDirectory(atPath:) so macOS
            // Sequoia Cryptex symlinks (Safari, Mail, Maps) are not silently skipped.
            collectApps(in: dir, into: &apps)
        }

        return apps.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Recursive scan of `dir`. Top-level .app bundles are added directly;
    /// non-.app directories are descended into. Stops descending into any .app.
    private static func collectApps(in dir: String, into apps: inout [URL]) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }

        for entry in entries where !entry.hasPrefix(".") {
            let fullPath = (dir as NSString).appendingPathComponent(entry)
            if entry.hasSuffix(".app") {
                apps.append(URL(fileURLWithPath: fullPath))
                continue
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                collectApps(in: fullPath, into: &apps)
            }
        }
    }
}
