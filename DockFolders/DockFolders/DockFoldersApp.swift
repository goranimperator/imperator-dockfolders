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
            ProcessInfo.processInfo.setValue("Imperator Dock Folders", forKey: "processName")
        }
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupDarwinListener()
            setupWakeListener()
            DockIconLocator.shared.requestAccessIfNeeded()
            Task.detached(priority: .utility) {
                LauncherGenerator.ensureMouseposHelper()
                LauncherGenerator.updateAllLauncherScripts()
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
        window.title = "Imperator Dock Folders"
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

    private func setupWakeListener() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.store.reload()
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

    private func openFolderPopup(named folderName: String, mousePosition: NSPoint? = nil) {
        guard let folder = store.folders.first(where: { $0.name == folderName })
                ?? store.loadFolder(named: folderName) else { return }

        // Try exact dock icon position via Accessibility API, fall back to mouse position
        let iconCenter = DockIconLocator.shared.iconCenter(forLauncherNamed: folderName)
        let position = iconCenter ?? mousePosition ?? NSEvent.mouseLocation

        FolderPopupController.shared.show(
            folder: folder,
            mousePosition: position
        )
    }
}

@main
struct DockFoldersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true

    var body: some Scene {
        MenuBarExtra("Imperator Dock Folders", systemImage: "square.grid.2x2", isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environmentObject(appDelegate.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
