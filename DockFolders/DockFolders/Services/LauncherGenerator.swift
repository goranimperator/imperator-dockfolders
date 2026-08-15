import AppKit
import CryptoKit

class LauncherGenerator {
    static var launchersURL: URL {
        DockFoldersPath.baseURL.appendingPathComponent(".launchers")
    }

    static func launcherURL(for folderURL: URL) -> URL {
        let name = folderURL.lastPathComponent
        return launchersURL.appendingPathComponent("\(name).app")
    }

    /// Plist key stamping which helper binary a launcher bundle was built with.
    /// updateAllLaunchersIfNeeded() compares it against the running app's helper
    /// to decide whether a bundle needs regeneration.
    private static let helperHashKey = "DFHelperHash"

    private static var bundledHelperURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "mousepos")
    }

    /// SHA-256 of the helper shipped inside the running app. Cached; the bundle
    /// is immutable while the app runs.
    private static let bundledHelperHash: String? = {
        guard let url = bundledHelperURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }()

    static func generateLauncher(for folderURL: URL) {
        let fm = FileManager.default
        let name = folderURL.lastPathComponent
        let appURL = launcherURL(for: folderURL)

        // Build the complete bundle in a hidden staging directory, then swap it
        // into place. The bundle must never exist half-written at its real path:
        // the Dock re-harvests icons when a tile's bundle changes on disk, and a
        // scan that catches the bundle before AppIcon.icns lands gets cached as
        // "no icon" -- a white generic tile until the cache is flushed.
        //
        // The staging name is unique per invocation: generateLauncher runs both
        // from the launch-time detached task and from MainActor mutation paths
        // with no lock, so a shared staging path would let two builds of the
        // same folder delete each other's half-built trees and swap a fragment
        // bundle into the live path. Unique names make concurrent builds
        // independent; the final swap is last-writer-wins between complete
        // bundles, which is fine.
        ensureLaunchersDirectory()
        let stagingURL = launchersURL.appendingPathComponent(".staging-\(UUID().uuidString).app")
        let contentsURL = stagingURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")

        do {
            try fm.createDirectory(at: macosURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        let safeBundleId = name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()

        var plist: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleIdentifier": "com.imperator.dockfolders.launcher.\(safeBundleId)",
            "CFBundleName": name,
            "CFBundleIconFile": "AppIcon",
            "CFBundleVersion": "1.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        if let hash = bundledHelperHash {
            plist[helperHashKey] = hash
        }
        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        (plist as NSDictionary).write(to: plistURL, atomically: true)

        // The executable is the prebuilt launcher helper (MouseLocation/main.swift),
        // not a shell script: one binary does mouse capture, handoff write, Darwin
        // notify / background app launch in-process. The old bash + mousepos +
        // pgrep + notifyutil chain spawned four processes per Dock click. The
        // helper derives the folder name from its own bundle path, so the same
        // binary is copied verbatim into every launcher.
        let launchURL = macosURL.appendingPathComponent("launch")
        if let bundled = bundledHelperURL {
            try? fm.copyItem(at: bundled, to: launchURL)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchURL.path)
        }

        let icon = IconGenerator.generateIconImage(for: folderURL)
        Self.writeIcnsToBundle(icon, at: stagingURL)

        // The bundle already carries the current DFHelperHash, so a partial
        // build must never reach the live path: updateAllLaunchersIfNeeded would
        // see it as current and skip it forever (dead click / white tile with no
        // self-heal). Abort and keep the old bundle -- its stale hash guarantees
        // a retry at the next launch.
        let required = [
            launchURL,
            plistURL,
            stagingURL.appendingPathComponent("Contents/Resources/AppIcon.icns"),
        ]
        guard required.allSatisfy({ fm.fileExists(atPath: $0.path) }) else {
            try? fm.removeItem(at: stagingURL)
            return
        }

        // Atomic swap into the real path. moveItem fails if the destination
        // exists; replaceItemAt covers that, including a destination created by
        // a concurrent build between the two calls.
        do {
            try fm.moveItem(at: stagingURL, to: appURL)
        } catch {
            _ = try? fm.replaceItemAt(appURL, withItemAt: stagingURL)
        }
        try? fm.removeItem(at: stagingURL)
    }

    static func removeLauncher(for folderURL: URL) {
        try? FileManager.default.removeItem(at: launcherURL(for: folderURL))
    }

    /// Regenerate launcher bundles whose embedded helper differs from the one in
    /// the running app (old shell-script bundles have no hash and always miss).
    /// Skips bundles that are already current, so a normal app launch touches
    /// nothing on disk and the Dock never re-harvests icons for no reason.
    /// Returns true if anything was regenerated.
    @discardableResult
    static func updateAllLaunchersIfNeeded() -> Bool {
        let fm = FileManager.default
        guard let expectedHash = bundledHelperHash,
              fm.fileExists(atPath: launchersURL.path),
              let contents = try? fm.contentsOfDirectory(
                  at: launchersURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else { return false }

        let baseURL = DockFoldersPath.baseURL
        var changed = false
        for appURL in contents where appURL.pathExtension == "app" {
            let name = appURL.deletingPathExtension().lastPathComponent
            let folderURL = baseURL.appendingPathComponent(name)
            guard fm.fileExists(atPath: folderURL.path) else { continue }

            let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
            let current = NSDictionary(contentsOf: plistURL)?[helperHashKey] as? String
            if current != expectedHash {
                generateLauncher(for: folderURL)
                changed = true
            }
        }
        return changed
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
        guard let bundled = bundledHelperURL else { return }

        ensureLaunchersDirectory()
        let helperURL = launchersURL.appendingPathComponent("mousepos")

        // Overwrite on every launch rather than copying once: self-heals a stale
        // or wrong-architecture helper left behind by an older version. Copy to a
        // temp name and rename so a pre-1.0.1 launcher script never execs a
        // half-copied binary.
        let tmpURL = launchersURL.appendingPathComponent(".mousepos-\(UUID().uuidString)")
        do {
            try fm.copyItem(at: bundled, to: tmpURL)
            _ = try? fm.replaceItemAt(helperURL, withItemAt: tmpURL)
            if fm.fileExists(atPath: tmpURL.path), !fm.fileExists(atPath: helperURL.path) {
                try fm.moveItem(at: tmpURL, to: helperURL)
            }
        } catch {
            try? fm.removeItem(at: tmpURL)
        }
        try? fm.removeItem(at: tmpURL)
    }
}
