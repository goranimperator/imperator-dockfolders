// Launcher helper. Compiled by the "Build mousepos Helper" build phase and
// copied into every generated launcher bundle as Contents/MacOS/launch.
//
// This replaces the old bash script + mousepos + pgrep + notifyutil chain:
// four process spawns per Dock click became one binary doing the same work
// in-process, which is what keeps click-to-popup fast.
//
// Behavior (identical contract to the old script):
//   1. Capture the mouse position via CGEvent.
//   2. Write "<folder name>\n<x>\n<y>" to /tmp/dockfolders_open.
//   3. App running: post the Darwin notification com.dockfolders.open.
//      App not running: launch it in the background WITHOUT notifying --
//      Darwin notifications are not queued, so the app consumes the handoff
//      file itself at launch (consumePendingHandoff in the main app).
//
// The folder name is derived from the bundle this binary runs inside
// (.../<FolderName>.app/Contents/MacOS/launch), so one identical binary
// serves every launcher bundle.

import AppKit

let appBundleID = "com.dockfolders.app"
let mainAppProcessName = "Imperator DockFolders"

// Mouse position, top-left origin (the app converts to AppKit coordinates).
let location = CGEvent(source: nil)?.location ?? .zero

// Folder name from our own bundle path.
let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let bundleURL = execURL            // .../<Name>.app/Contents/MacOS/launch
    .deletingLastPathComponent()   // MacOS
    .deletingLastPathComponent()   // Contents
    .deletingLastPathComponent()   // <Name>.app
let folderName = bundleURL.deletingPathExtension().lastPathComponent
guard !folderName.isEmpty, bundleURL.pathExtension == "app" else {
    // Not running inside a launcher bundle: this is the copy mirrored to
    // .launchers/mousepos, which pre-1.0.1 launcher scripts exec expecting
    // the mouse position on stdout ("x\ny"). Honor that contract.
    print(String(format: "%.0f", location.x))
    print(String(format: "%.0f", location.y))
    exit(0)
}
let handoff = String(format: "%@\n%.0f\n%.0f", folderName, location.x, location.y)
try? handoff.write(toFile: "/tmp/dockfolders_open", atomically: true, encoding: .utf8)

let running = !NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).isEmpty

if running {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName("com.dockfolders.open" as CFString),
        nil, nil, true
    )
} else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.addsToRecentItems = false
    config.arguments = ["--background"]
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
        done.signal()
    }
    _ = done.wait(timeout: .now() + 5)
}
