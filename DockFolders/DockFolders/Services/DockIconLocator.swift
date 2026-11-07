import AppKit
import ApplicationServices

/// Locates dock icon positions via the Accessibility API.
/// Requires Accessibility permission (non-sandboxed app).
class DockIconLocator {
    static let shared = DockIconLocator()

    /// Returns the screen-space center point of the Dock tile for the folder
    /// with this name. Nil if Accessibility is unavailable or the folder is not
    /// in the Dock; callers then fall back to the mouse position.
    ///
    /// Tiles are matched on the file they stand for (`AXURL`), never on their
    /// title. A folder named after an app in the same Dock, say "Safari", has
    /// the same title as that app's tile, and matching on the title anchored
    /// the folder's popup over Safari and let a click on Safari open the folder.
    /// See `LauncherGenerator.folderName(forDockURL:)`.
    func iconCenter(forLauncherNamed name: String) -> NSPoint? {
        guard let element = findDockItem(forFolderNamed: name) else { return nil }
        return axCenterPoint(of: element)
    }

    /// Request Accessibility permission if not yet granted.
    func requestAccessIfNeeded() {
        // The value of kAXTrustedCheckOptionPrompt. Swift 6 rejects reading that
        // imported C global as shared mutable state, so the key is spelled out.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Cached union frame of the Dock item list (AppKit coordinates), used as a
    /// cheap gate so the global click monitor does one rect test per click
    /// instead of an AX round-trip. Refreshed lazily.
    private var dockFrame: NSRect?
    private var dockFrameStamp: Date = .distantPast

    /// If `point` (AppKit bottom-left coordinates) is on the Dock tile of one of
    /// the folders in `names`, return that folder's name and the tile's center.
    /// One AX position query when the point is inside the Dock region; pure math
    /// otherwise. Tiles are matched on the file they stand for, never their
    /// title (see `iconCenter(forLauncherNamed:)`).
    func folderTile(at point: NSPoint, matching names: Set<String>) -> (name: String, center: NSPoint)? {
        guard AXIsProcessTrusted(), !names.isEmpty else { return nil }

        if dockFrame == nil || Date().timeIntervalSince(dockFrameStamp) > 30 {
            dockFrame = currentDockFrame()
            dockFrameStamp = Date()
        }
        guard let frame = dockFrame, frame.insetBy(dx: -8, dy: -8).contains(point) else {
            return nil
        }

        // Enumerate Dock tiles and match on frame. A systemwide
        // AXUIElementCopyElementAtPosition hit-test does not resolve Dock tiles
        // reliably, so this reuses the same enumeration findDockItem(forFolderNamed:) uses.
        guard let dockPID = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first?.processIdentifier else { return nil }
        let dockApp = AXUIElementCreateApplication(dockPID)
        guard let dockList = axChildren(of: dockApp)?.first,
              let items = axChildren(of: dockList) else { return nil }

        for item in items {
            guard let url = axURL(of: item),
                  let name = LauncherGenerator.folderName(forDockURL: url), names.contains(name),
                  let itemFrame = axFrame(of: item) else { continue }
            if itemFrame.insetBy(dx: -2, dy: -2).contains(point) {
                return (name, NSPoint(x: itemFrame.midX, y: itemFrame.midY))
            }
        }
        return nil
    }

    /// Element frame in AppKit bottom-left coordinates.
    private func axFrame(of element: AXUIElement) -> NSRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        // AX flips against the PRIMARY screen (the menu bar one), never
        // NSScreen.main: that is the key window's screen, and with two displays
        // of different heights it put every Dock tile off by the difference.
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: position.x, y: screenH - position.y - size.height,
                      width: size.width, height: size.height)
    }

    private func currentDockFrame() -> NSRect? {
        guard let dockPID = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first?.processIdentifier else { return nil }
        let dockApp = AXUIElementCreateApplication(dockPID)
        guard let dockList = axChildren(of: dockApp)?.first else { return nil }

        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockList, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(dockList, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        let screenH = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: position.x, y: screenH - position.y - size.height,
                      width: size.width, height: size.height)
    }

    // MARK: - Private

    private func findDockItem(forFolderNamed name: String) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        guard let dockPID = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first?.processIdentifier else { return nil }

        let dockApp = AXUIElementCreateApplication(dockPID)

        guard let dockList = axChildren(of: dockApp)?.first,
              let items = axChildren(of: dockList) else { return nil }

        return items.first { item in
            axURL(of: item).flatMap(LauncherGenerator.folderName(forDockURL:)) == name
        }
    }

    private func axCenterPoint(of element: AXUIElement) -> NSPoint? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        // CFTypeRef → AXValue is a toll-free bridge; the guard on Copy above ensures non-nil.
        let posAX = posValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        guard AXValueGetValue(posAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size)
        else { return nil }

        // AX coordinates are top-left origin, convert to AppKit bottom-left.
        // Against the primary screen, as in axFrame(of:).
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let centerX = position.x + size.width / 2
        let centerY = screenH - (position.y + size.height / 2)

        return NSPoint(x: centerX, y: centerY)
    }

    private func axChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let children = value as? [AXUIElement] else { return nil }
        return children
    }

    /// The file the tile stands for: an app, a folder, or one of our launcher
    /// bundles. Nil for separators and the Trash.
    private func axURL(of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value)
        guard result == .success, let url = value as? URL else { return nil }
        return url
    }
}
