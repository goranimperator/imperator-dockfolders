import AppKit
import ApplicationServices

/// Position info for a dock icon in AppKit screen coordinates (bottom-left origin).
struct DockIconPosition {
    let centerX: CGFloat
    let topY: CGFloat  // Y of the top edge of the icon
}

/// Locates dock icon positions via the Accessibility API.
/// Requires Accessibility permission (non-sandboxed app).
class DockIconLocator {
    static let shared = DockIconLocator()

    /// Returns position info (center X + top Y) for a dock icon.
    func iconPosition(forLauncherNamed name: String) -> DockIconPosition? {
        guard let element = findDockItem(named: name) else { return nil }
        return axPosition(of: element)
    }

    /// Returns the screen-space center point of a dock icon matching the given launcher name.
    /// Falls back to nil if Accessibility is unavailable or the icon isn't found.
    func iconCenter(forLauncherNamed name: String) -> NSPoint? {
        guard let element = findDockItem(named: name) else { return nil }
        guard let pos = axPosition(of: element) else { return nil }
        // Reconstruct center Y from topY (need size again, so use cached center calc)
        return axCenterPoint(of: element)
    }

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

    /// Request Accessibility permission if not yet granted.
    func requestAccessIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func axPosition(of element: AXUIElement) -> DockIconPosition? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        // AX coordinates are top-left origin, convert to AppKit bottom-left
        let screenH = NSScreen.main?.frame.height ?? 0
        let centerX = position.x + size.width / 2
        // Top edge in AX = position.y, in AppKit = screenH - position.y
        let topY = screenH - position.y

        return DockIconPosition(centerX: centerX, topY: topY)
    }

    // MARK: - AX Helpers

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

    private func axCenterPoint(of element: AXUIElement) -> NSPoint? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        // AX coordinates are top-left origin, convert to AppKit bottom-left
        let screenH = NSScreen.main?.frame.height ?? 0
        let centerX = position.x + size.width / 2
        let centerY = screenH - (position.y + size.height / 2)

        return NSPoint(x: centerX, y: centerY)
    }
}
