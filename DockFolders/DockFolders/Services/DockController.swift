import Foundation

class DockController {
    static let shared = DockController()

    private func dockURLVariants(for path: String) -> [String] {
        let withSpaces = "file://" + path
        let encoded = "file://" + path.replacingOccurrences(of: " ", with: "%20")
        // macOS stores dock URLs with and without trailing slash
        return [withSpaces, encoded, withSpaces + "/", encoded + "/"]
    }

    private func matchesFolder(_ urlString: String, folderURL: URL) -> Bool {
        let launcherPath = LauncherGenerator.launcherURL(for: folderURL).path
        let folderPath = folderURL.path + "/"
        let allVariants = dockURLVariants(for: launcherPath) + dockURLVariants(for: folderPath)
        return allVariants.contains(urlString)
    }

    private var cachedDockURLs: Set<String>?

    /// Read all dock URLs once per batch of isFolderInDock calls.
    /// Call invalidateDockCache() after modifying the dock.
    private func dockURLSet() -> Set<String> {
        if let cached = cachedDockURLs { return cached }
        let apps = readDockSection("persistent-apps")
        let others = readDockSection("persistent-others")
        var urls = Set<String>()
        for entry in apps + others {
            if let tileData = entry["tile-data"] as? [String: Any],
               let fileData = tileData["file-data"] as? [String: Any],
               let urlString = fileData["_CFURLString"] as? String {
                urls.insert(urlString)
            }
        }
        cachedDockURLs = urls
        return urls
    }

    func invalidateDockCache() {
        cachedDockURLs = nil
    }

    func isFolderInDock(_ folderURL: URL) -> Bool {
        let urls = dockURLSet()
        let launcherPath = LauncherGenerator.launcherURL(for: folderURL).path
        let folderPath = folderURL.path + "/"
        let allVariants = dockURLVariants(for: launcherPath) + dockURLVariants(for: folderPath)
        return allVariants.contains { urls.contains($0) }
    }

    func addToDock(_ folderURL: URL) {
        invalidateDockCache()
        guard !isFolderInDock(folderURL) else { return }

        LauncherGenerator.ensureLaunchersDirectory()
        LauncherGenerator.generateLauncher(for: folderURL)

        let launcherPath = LauncherGenerator.launcherURL(for: folderURL).path
        let escapedPath = launcherPath.replacingOccurrences(of: " ", with: "%20")
        let urlString = "file://\(escapedPath)"

        let plistXML = """
        <dict>
            <key>tile-data</key>
            <dict>
                <key>file-data</key>
                <dict>
                    <key>_CFURLString</key><string>\(urlString)</string>
                    <key>_CFURLStringType</key><integer>15</integer>
                </dict>
            </dict>
            <key>tile-type</key><string>file-tile</string>
        </dict>
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.dock", "persistent-apps", "-array-add", plistXML]
        try? process.run()
        process.waitUntilExit()

        refreshDock()
    }

    func removeFromDock(_ folderURL: URL) {
        invalidateDockCache()
        removeFromSection("persistent-apps", folderURL: folderURL)
        removeFromSection("persistent-others", folderURL: folderURL)
        LauncherGenerator.removeLauncher(for: folderURL)
        refreshDock()
    }

    private func removeFromSection(_ section: String, folderURL: URL) {
        var plist = readDockSection(section)
        let before = plist.count

        plist.removeAll { entry in
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String else { return false }
            return matchesFolder(urlString, folderURL: folderURL)
        }

        if plist.count < before {
            writeDockSection(section, entries: plist)
        }
    }

    func refreshDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        process.waitUntilExit()
    }

    private func readDockSection(_ section: String) -> [[String: Any]] {
        guard let value = CFPreferencesCopyAppValue(
            section as CFString,
            "com.apple.dock" as CFString
        ) else { return [] }
        return value as? [[String: Any]] ?? []
    }

    private func writeDockSection(_ section: String, entries: [[String: Any]]) {
        let clearProcess = Process()
        clearProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        clearProcess.arguments = ["write", "com.apple.dock", section, "-array"]
        try? clearProcess.run()
        clearProcess.waitUntilExit()

        for entry in entries {
            guard let entryData = try? PropertyListSerialization.data(fromPropertyList: entry, format: .xml, options: 0),
                  let entryString = String(data: entryData, encoding: .utf8) else { continue }
            let addProcess = Process()
            addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            addProcess.arguments = ["write", "com.apple.dock", section, "-array-add", entryString]
            try? addProcess.run()
            addProcess.waitUntilExit()
        }
    }
}
