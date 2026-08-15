import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let store = FolderStore()
    private var mainWindow: NSWindow?

    nonisolated func applicationWillFinishLaunching(_ notification: Notification) {
        // BrandBook 14.1 / 14.2 / 15.2: force dark mode, override system accent,
        // and set the process name before any window appears.
        Task { @MainActor in
            NSApp.appearance = NSAppearance(named: .darkAqua)
            UserDefaults.standard.set(0, forKey: "AppleAccentColor")
            ProcessInfo.processInfo.setValue("Imperator DockFolders", forKey: "processName")
        }
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupDarwinListener()
            consumePendingHandoff()
            // Warm SwiftUI layout, panel and material once so the first real
            // popup skips its one-time setup cost. Largest folder = worst-case
            // layout warmed.
            if let folder = store.folders.max(by: { $0.apps.count < $1.apps.count }) {
                FolderPopupController.shared.prewarm(folder: folder)
            }
            setupWakeListener()
            DockIconLocator.shared.requestAccessIfNeeded()
            setupDockClickMonitor()
            Task.detached(priority: .utility) {
                LauncherGenerator.ensureMouseposHelper()
                // Only bundles whose helper is stale get rewritten; a Dock
                // restart re-harvests their tile icons (regeneration invalidates
                // the Dock's icon cache, which otherwise shows a white tile).
                if LauncherGenerator.updateAllLaunchersIfNeeded() {
                    await DockController.shared.refreshDock()
                }
            }
            let showWindow = UserDefaults.standard.object(forKey: "showMainWindow") as? Bool ?? true
            if showWindow && !CommandLine.arguments.contains("--background") {
                showMainWindow()
            }
        }
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            showMainWindow()
        }
        return true
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            mainWindow = nil
        }
    }

    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                guard url.scheme == "dockfolders", url.host == "open" else { continue }
                let name = url.pathComponents.dropFirst().joined(separator: "/")
                    .removingPercentEncoding ?? ""
                guard !name.isEmpty else { continue }
                openFolderPopup(named: name)
            }
        }
    }

    func showMainWindow() {
        if let w = mainWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let contentView = ContentView()
            .environmentObject(store)
            .frame(minWidth: 600, minHeight: 400)

        let window = mainWindow ?? {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.isReleasedWhenClosed = false
            w.delegate = self
            return w
        }()
        window.contentView = NSHostingView(rootView: contentView)
        window.title = "Imperator DockFolders"
        window.setFrameAutosaveName("MainWindow")
        if mainWindow == nil { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        mainWindow = window
    }

    private func setupDarwinListener() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let ptr = observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                Task { @MainActor in
                    delegate.handleDarwinNotification()
                }
            },
            "com.dockfolders.open" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private var clickTap: CFMachPort?

    /// Fast path for Dock clicks. The Dock tile click still makes LaunchServices
    /// spawn the launcher (~100ms to popup); this listen-only CGEvent tap sees
    /// the same mouse-up directly, AX-hit-tests the Dock tile and opens the
    /// popup in ~15-25ms. The launcher's Darwin notification arrives later and
    /// is deduped in show(). The tap needs Accessibility; without the grant
    /// tapCreate returns nil and the launcher path serves every click, exactly
    /// as before.
    private func setupDockClickMonitor() {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                switch type {
                case .leftMouseUp:
                    let location = event.location
                    Task { @MainActor in delegate.handleDockClick(topLeft: location) }
                case .leftMouseDown, .rightMouseDown:
                    let location = event.location
                    Task { @MainActor in
                        let screenH = NSScreen.screens.first?.frame.height ?? 0
                        FolderPopupController.shared.handleGlobalMouseDown(
                            screenPoint: NSPoint(x: location.x, y: screenH - location.y)
                        )
                    }
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    Task { @MainActor in delegate.reenableClickTap() }
                default:
                    break
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        clickTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func reenableClickTap() {
        if let tap = clickTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func handleDockClick(topLeft: CGPoint) {
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let point = NSPoint(x: topLeft.x, y: screenH - topLeft.y)
        let names = Set(store.folders.map(\.name))
        guard let tile = DockIconLocator.shared.folderTile(at: point, matching: names) else { return }
        openFolderPopup(named: tile.name, knownIconCenter: tile.center)
    }

    private func setupWakeListener() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.store.reload()
        }
    }

    /// Consume a handoff the launcher wrote while we were still starting up.
    /// Darwin notifications are not queued: a launcher that starts the app and
    /// posts immediately loses the notification if it lands before
    /// setupDarwinListener() has run, which left the first Dock click after
    /// login without a popup. The launcher script therefore no longer waits and
    /// notifies on a cold start -- it writes the handoff file, starts the app,
    /// and this reads it as soon as the listener is in place.
    private func consumePendingHandoff() {
        let path = "/tmp/dockfolders_open"
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return }
        // Only act on a fresh click; a stale file from an old crashed click
        // must not pop a folder when the app is launched manually later.
        if Date().timeIntervalSince(mtime) < 10 {
            handleDarwinNotification()
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func handleDarwinNotification() {
        let path = "/tmp/dockfolders_open"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(atPath: path)

        let parts = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        guard let folderName = parts.first, !folderName.isEmpty else { return }

        var mousePos: NSPoint?
        if parts.count >= 3,
           let mx = Double(parts[1]),
           let my = Double(parts[2]) {
            let screenH = NSScreen.main?.frame.height ?? 0
            mousePos = NSPoint(x: mx, y: screenH - my)
        }

        openFolderPopup(named: folderName, mousePosition: mousePos)
    }

    private func openFolderPopup(named folderName: String, mousePosition: NSPoint? = nil,
                                 knownIconCenter: NSPoint? = nil) {
        guard let folder = store.folders.first(where: { $0.name == folderName })
                ?? store.loadFolder(named: folderName) else { return }

        // Exact dock icon position: already known from the click monitor's AX
        // hit-test, otherwise one Accessibility lookup. Passed through to show()
        // so it never repeats the AX round-trip.
        let iconCenter = knownIconCenter
            ?? DockIconLocator.shared.iconCenter(forLauncherNamed: folderName)
        let position = iconCenter ?? mousePosition ?? NSEvent.mouseLocation

        FolderPopupController.shared.show(
            folder: folder,
            mousePosition: position,
            iconCenter: iconCenter
        )
    }
}

@main
struct DockFoldersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true

    var body: some Scene {
        MenuBarExtra("Imperator DockFolders", systemImage: "square.grid.2x2", isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environmentObject(appDelegate.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
