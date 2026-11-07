import Foundation

@MainActor
class DockController {
    static let shared = DockController()

    private func dockURLVariants(for path: String) -> [String] {
        let withSpaces = "file://" + path
        let encoded = "file://" + path.replacingOccurrences(of: " ", with: "%20")
        // macOS stores dock URLs with and without trailing slash
        return [withSpaces, encoded, withSpaces + "/", encoded + "/"]
    }

    /// Whether a Dock entry's URL string is this folder's tile. Parsed and
    /// matched by path through `LauncherGenerator.folderName(forDockURL:)`, the
    /// same rule DockIconLocator uses. The raw string variants stay as a second
    /// check for entries written before the URL was properly encoded: a name
    /// with `#` in it was stored unescaped and does not parse back to its path.
    private func matchesFolder(_ urlString: String, folderURL: URL) -> Bool {
        if let url = URL(string: urlString),
           LauncherGenerator.folderName(forDockURL: url) == folderURL.lastPathComponent {
            return true
        }
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
        dockURLSet().contains { matchesFolder($0, folderURL: folderURL) }
    }

    func addToDock(_ folderURL: URL) {
        invalidateDockCache()
        guard !isFolderInDock(folderURL) else { return }

        LauncherGenerator.ensureLaunchersDirectory()
        LauncherGenerator.generateLauncher(for: folderURL)

        // A real file URL, so every reserved character is encoded. Escaping only
        // spaces left `#`, `?` and `%` raw, and a name like "Dev #1" was stored
        // as a URL whose path stops at "Dev ".
        let urlString = URL(fileURLWithPath: LauncherGenerator.launcherURL(for: folderURL).path).absoluteString
        // The plist below is XML: a folder named "Tools & Utils" made it invalid
        // and `defaults` then silently added nothing.
        let xmlURLString = urlString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let plistXML = """
        <dict>
            <key>tile-data</key>
            <dict>
                <key>file-data</key>
                <dict>
                    <key>_CFURLString</key><string>\(xmlURLString)</string>
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
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0),
              let xmlString = String(data: data, encoding: .utf8) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.dock", section, xmlString]
        try? process.run()
        process.waitUntilExit()
    }
}
