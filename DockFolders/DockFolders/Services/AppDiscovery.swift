import Foundation
import AppKit

/// Which mounted volumes `AppDiscovery` is allowed to walk. Lives in
/// UserDefaults so the settings pane and the scan read the same values.
enum VolumeScanSettings {
    static let scanEnabledKey = "scanExternalDrives"
    static let excludedVolumesKey = "excludedVolumeNames"

    /// On by default: an app on an external disk is unreachable from the picker
    /// otherwise, and the scan below is depth-capped. `bool(forKey:)` reports
    /// an unset key as false, so the default is read through `object(forKey:)`.
    static var scanExternalDrives: Bool {
        get { UserDefaults.standard.object(forKey: scanEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: scanEnabledKey) }
    }

    /// Volume names the user switched off individually. Keyed by name rather
    /// than mount path because the path is just /Volumes/<name>, and the name
    /// is what the user sees in Settings and in Finder.
    static var excludedVolumeNames: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: excludedVolumesKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: excludedVolumesKey) }
    }

    static func isExcluded(_ volumeName: String) -> Bool {
        excludedVolumeNames.contains(volumeName)
    }

    static func setExcluded(_ excluded: Bool, for volumeName: String) {
        var names = excludedVolumeNames
        if excluded {
            names.insert(volumeName)
        } else {
            names.remove(volumeName)
        }
        excludedVolumeNames = names
    }
}

class AppDiscovery {
    /// How many levels below a mounted volume's root the scan descends. A
    /// removable disk is a whole filesystem, not a curated /Applications, so
    /// the walk is capped: Game.app directly on the disk, in a folder on it,
    /// or one level below that. Anything deeper is added through the picker's
    /// "Choose Apps" button instead of by scanning.
    private static let volumeScanDepth = 3

    /// Never descended into on a mounted volume. A Time Machine store holds
    /// every app of every backed-up Mac, which would bury the disk's own apps
    /// and make the scan as slow as the backup is large.
    private static let skippedDirectoryNames: Set<String> = ["Backups.backupdb"]

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
            collectApps(in: dir, into: &apps, depthRemaining: nil)
        }

        if VolumeScanSettings.scanExternalDrives {
            for volume in scannableVolumes() {
                collectApps(in: volume.path, into: &apps, depthRemaining: volumeScanDepth)
            }
        }

        return apps.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Mounted external volumes, before the user's own exclusions. Settings
    /// lists these so a disk can be switched off one at a time.
    ///
    /// The boot volume is left out because the fixed search paths above already
    /// cover it, a network share is left out because `contentsOfDirectory` on
    /// one blocks for as long as the server takes to answer, and an internal or
    /// non-browsable volume is not what "external drive" means to the user.
    static func externalVolumes() -> [URL] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey,
            .volumeIsLocalKey,
            .volumeIsRootFileSystemKey
        ]

        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return volumes.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            guard values.volumeIsRootFileSystem != true,
                  values.volumeIsBrowsable == true,
                  values.volumeIsLocal == true,
                  values.volumeIsInternal != true else { return false }
            return values.volumeName != nil
        }
    }

    static func volumeName(for volume: URL) -> String {
        let name = try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName
        return name ?? volume.lastPathComponent
    }

    private static func scannableVolumes() -> [URL] {
        externalVolumes().filter { !VolumeScanSettings.isExcluded(volumeName(for: $0)) }
    }

    /// Recursive scan of `dir`. Top-level .app bundles are added directly;
    /// non-.app directories are descended into. Stops descending into any .app.
    /// `depthRemaining` nil scans without a limit; a value stops the walk that
    /// many levels down.
    private static func collectApps(in dir: String, into apps: inout [URL], depthRemaining: Int?) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }

        for entry in entries where !entry.hasPrefix(".") {
            let fullPath = (dir as NSString).appendingPathComponent(entry)
            if entry.hasSuffix(".app") {
                apps.append(URL(fileURLWithPath: fullPath))
                continue
            }
            if skippedDirectoryNames.contains(entry) { continue }
            if let depthRemaining, depthRemaining <= 1 { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                collectApps(in: fullPath, into: &apps, depthRemaining: depthRemaining.map { $0 - 1 })
            }
        }
    }
}
