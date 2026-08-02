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
            "CFBundleIconFile": "AppIcon",
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
        if ! /usr/bin/pgrep -xq "Imperator DockFolders"; then
          /usr/bin/open -g -b com.dockfolders.app --args --background
          for i in $(seq 1 20); do /usr/bin/pgrep -xq "Imperator DockFolders" && break; sleep 0.05; done
        fi
        /usr/bin/notifyutil -p com.dockfolders.open
        """
        let scriptURL = macosURL.appendingPathComponent("launch")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let icon = IconGenerator.generateIconImage(for: folderURL)
        Self.writeIcnsToBundle(icon, at: appURL)
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

    static func writeIcnsToBundle(_ image: NSImage, at appURL: URL) {
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources")
        try? FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".iconset")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = size * scale
                let suffix = scale == 1 ? "" : "@2x"
                let resized = NSImage(size: NSSize(width: px, height: px))
                resized.lockFocus()
                image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                resized.unlockFocus()
                if let tiff = resized.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    let name = "icon_\(size)x\(size)\(suffix).png"
                    try? png.write(to: tmpDir.appendingPathComponent(name))
                }
            }
        }

        let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o", icnsURL.path, tmpDir.path]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: tmpDir)
    }

    static func ensureLaunchersDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: launchersURL.path) {
            try? fm.createDirectory(at: launchersURL, withIntermediateDirectories: true)
        }
    }

    /// Copy the prebuilt mouse-position helper out of the app bundle into the
    /// launchers directory, where the generated launcher scripts can run it.
    ///
    /// The helper is compiled by the "Build mousepos Helper" build phase and
    /// ships signed inside `Contents/MacOS`. It used to be compiled here at
    /// runtime via `/usr/bin/swiftc`, but that is an xcode-select shim: on a Mac
    /// without developer tools it pops the "Install Command Line Developer
    /// Tools" system dialog at the user on first launch.
    static func ensureMouseposHelper() {
        let fm = FileManager.default
        guard let bundled = Bundle.main.url(forAuxiliaryExecutable: "mousepos") else { return }

        ensureLaunchersDirectory()
        let helperURL = launchersURL.appendingPathComponent("mousepos")

        // Overwrite on every launch rather than copying once: self-heals a stale
        // or wrong-architecture helper left behind by an older version.
        try? fm.removeItem(at: helperURL)
        try? fm.copyItem(at: bundled, to: helperURL)
    }
}
