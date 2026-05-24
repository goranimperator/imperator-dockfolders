import Foundation
import AppKit

class AppDiscovery {
    static func installedApps() -> [URL] {
        let fm = FileManager.default
        var apps: [URL] = []

        var searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        // Include apps bundled inside Xcode (Icon Composer, Instruments, etc.)
        let xcodeApps = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Applications")
        if fm.fileExists(atPath: xcodeApps.path) {
            searchPaths.append(xcodeApps)
        }

        for searchPath in searchPaths {
            guard let enumerator = fm.enumerator(
                at: searchPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    apps.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        return apps.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}
