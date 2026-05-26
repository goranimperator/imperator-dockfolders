import AppKit
import ApplicationServices

/// Locates dock icon positions via the Accessibility API.
/// Requires Accessibility permission (non-sandboxed app).
class DockIconLocator {
    static let shared = DockIconLocator()

    /// Returns the screen-space center point of a dock icon matching the given launcher name.
    /// Falls back to nil if Accessibility is unavailable or the icon isn't found.
    func iconCenter(forLauncherNamed name: String) -> NSPoint? {
        guard let element = findDockItem(named: name) else { return nil }
        return axCenterPoint(of: element)
    }

    /// Request Accessibility permission if not yet granted.
    func requestAccessIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private

    private func findDockItem(named name: String) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        guard let dockPID = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first?.processIdentifier else { return nil }

        let dockApp = AXUIElementCreateApplication(dockPID)

        guard let dockList = axChildren(of: dockApp)?.first,
              let items = axChildren(of: dockList) else { return nil }

        for item in items {
            guard let title = axTitle(of: item) else { continue }
            if title == name {
                return item
            }
        }

        return nil
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

        // AX coordinates are top-left origin, convert to AppKit bottom-left
        let screenH = NSScreen.main?.frame.height ?? 0
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

    private func axTitle(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        guard result == .success, let title = value as? String else { return nil }
        return title
    }
}
