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

        let mouseposPath = launchersURL.appendingPathComponent("mousepos").path
        let script = """
        #!/bin/bash
        MOUSE=$("\(mouseposPath)" 2>/dev/null)
        printf '%s\\n%s' "\(name)" "$MOUSE" > /tmp/dockfolders_open
        if ! /usr/bin/pgrep -xq DockFolders; then
          /usr/bin/open -g -b com.dockfolders.app --args --background
          for i in $(seq 1 20); do /usr/bin/pgrep -xq DockFolders && break; sleep 0.05; done
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

    static func ensureMouseposHelper() {
        let fm = FileManager.default
        let helperURL = launchersURL.appendingPathComponent("mousepos")
        guard !fm.fileExists(atPath: helperURL.path) else { return }

        ensureLaunchersDirectory()

        let source = """
        import CoreGraphics
        let event = CGEvent(source: nil)
        let location = event?.location ?? .zero
        print(String(format: "%.0f", location.x))
        print(String(format: "%.0f", location.y))
        """

        let tmpSource = fm.temporaryDirectory.appendingPathComponent("mousepos.swift")
        try? source.write(to: tmpSource, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = ["-O", "-o", helperURL.path, tmpSource.path]
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            // Ad-hoc sign to avoid Gatekeeper delays
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--sign", "-", "--force", helperURL.path]
            try? sign.run()
            sign.waitUntilExit()
        }

        try? fm.removeItem(at: tmpSource)
    }
}
