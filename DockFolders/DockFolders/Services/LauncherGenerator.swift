import AppKit

class LauncherGenerator {
    static var launchersURL: URL {
        DockFoldersPath.baseURL.appendingPathComponent(".launchers")
    }

    static func launcherURL(for folderURL: URL) -> URL {
        let name = folderURL.lastPathComponent
        return launchersURL.appendingPathComponent("\(name).app")
    }

    static func generateLauncher(for folderURL: URL) {
        let fm = FileManager.default
        let name = folderURL.lastPathComponent
        let appURL = launcherURL(for: folderURL)
        let contentsURL = appURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")

        try? fm.removeItem(at: appURL)
        try? fm.createDirectory(at: macosURL, withIntermediateDirectories: true)

        let safeBundleId = name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()

        let plist: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleIdentifier": "com.imperator.dockfolders.launcher.\(safeBundleId)",
            "CFBundleName": name,
            "CFBundleVersion": "1.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        (plist as NSDictionary).write(to: plistURL, atomically: true)

        let script = """
        #!/bin/bash
        MOUSE=$(/usr/bin/python3 -c "from Quartz.CoreGraphics import CGEventGetLocation, CGEventCreate; e = CGEventCreate(None); l = CGEventGetLocation(e); print(f'{l.x:.0f}\\n{l.y:.0f}')" 2>/dev/null)
        printf '%s\\n%s' "\(name)" "$MOUSE" > /tmp/dockfolders_open
        if ! /usr/bin/pgrep -xq DockFolders; then
          /usr/bin/open -g -b com.dockfolders.app --args --background
          sleep 1
        fi
        /usr/bin/notifyutil -p com.dockfolders.open
        """
        let scriptURL = macosURL.appendingPathComponent("launch")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let icon = IconGenerator.generateIconImage(for: folderURL)
        NSWorkspace.shared.setIcon(icon, forFile: appURL.path, options: [])
    }

    static func removeLauncher(for folderURL: URL) {
        try? FileManager.default.removeItem(at: launcherURL(for: folderURL))
    }

    static func updateAllLauncherScripts() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: launchersURL.path),
              let contents = try? fm.contentsOfDirectory(
                  at: launchersURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else { return }

        let baseURL = DockFoldersPath.baseURL
        for appURL in contents where appURL.pathExtension == "app" {
            let name = appURL.deletingPathExtension().lastPathComponent
            let folderURL = baseURL.appendingPathComponent(name)
            if fm.fileExists(atPath: folderURL.path) {
                generateLauncher(for: folderURL)
            }
        }
    }

    static func ensureLaunchersDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: launchersURL.path) {
            try? fm.createDirectory(at: launchersURL, withIntermediateDirectories: true)
        }
    }
}
