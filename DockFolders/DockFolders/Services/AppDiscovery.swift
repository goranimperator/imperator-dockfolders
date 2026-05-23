import Foundation
import AppKit

class AppDiscovery {
    static func installedApps() -> [URL] {
        let fm = FileManager.default
        var apps: [URL] = []

        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

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
