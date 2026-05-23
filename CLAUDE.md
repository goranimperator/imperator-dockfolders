# Imperator Dock Folders

macOS app (Swift/SwiftUI/AppKit) that creates custom app folder shortcuts in the Dock. Minimum macOS 14, no App Sandbox.

## Architecture overview

The app creates folders in `~/Library/Application Support/DockFolders/`. Each folder contains symlinks to apps. When a folder is added to the Dock, a small launcher `.app` bundle is created and placed among regular apps in the Dock's `persistent-apps` section. Clicking the launcher icon triggers a custom popup above the Dock (not macOS built-in folder grid).

### File system as source of truth

```
~/Library/Application Support/DockFolders/
  FolderName/
    .gridconfig        <- JSON: {"columns": 3, "itemsPerPage": 9}
    .apporder          <- JSON: ["App1.app", "App2.app", ...]
    Safari.app         <- symlink -> /Applications/Safari.app
    Slack.app          <- symlink -> /Applications/Slack.app
  .launchers/
    FolderName.app/    <- generated launcher bundle
```

## Project structure

```
DockFolders/DockFolders/
  DockFoldersApp.swift      <- App entry point, AppDelegate, Darwin listener
  Info.plist                <- CFBundleIconFile, URL scheme (dockfolders://)
  Models/
    DockFolder.swift        <- DockFolder + GridConfig structs
    AppEntry.swift          <- AppEntry struct (icon, URL, name)
    AppearanceMode.swift    <- Enum: system/dark
  Services/
    FolderStore.swift       <- CRUD, grid config, reorder, dock toggle. DockFoldersPath enum.
    DockController.swift    <- Reads/writes com.apple.dock plist, persistent-apps
    IconGenerator.swift     <- Generates folder icons (rounded rect + app grid)
    LauncherGenerator.swift <- Creates launcher .app bundles with shell script
    AppDiscovery.swift      <- Scans /Applications + ~/Applications
    AppearanceObserver.swift <- Listens for dark/light mode changes
  Views/
    ContentView.swift       <- HSplitView with sidebar + detail
    FolderListView.swift    <- Sidebar: folder list
    FolderDetailView.swift  <- App grid with carousel, drag-reorder, grid settings
    FolderPopupPanel.swift  <- Custom NSPanel popup with arrow + visual effect
    AppPickerView.swift     <- Sheet for adding apps
    MenuBarView.swift       <- MenuBarExtra view
    SettingsView.swift      <- Settings (theme, menu bar)
    SigilShape.swift        <- Imperator sigil SVG as SwiftUI Shape
  Resources/
    Assets.xcassets/        <- App icon (all sizes)
    AppIcon.icns            <- .icns file for Finder display
```

## Key mechanisms

### IPC: Launcher -> App

1. Launcher script (`LauncherGenerator.swift`) runs on Dock click
2. Script captures mouse position via CoreGraphics Python bridge
3. Writes folder name + mouse coordinates to `/tmp/dockfolders_open`
4. If app is not running: launches it with `open -g -b com.dockfolders.app --args --background`
5. Sends Darwin notification via `notifyutil -p com.dockfolders.open`
6. AppDelegate listens with `CFNotificationCenterGetDarwinNotifyCenter()`
7. Reads `/tmp/dockfolders_open`, opens popup at mouse position

### Dock integration (`DockController.swift`)

- Places launchers in `persistent-apps` (not `persistent-others`)
- Writes directly to `com.apple.dock` plist via `defaults write`
- Handles URL variants with spaces and %20 encoding
- `killall Dock` to apply changes

### Popup panel (`FolderPopupPanel.swift`)

- `PopupPanel`: NSPanel subclass with `canBecomeKey = true`
- `PopupShape`: Custom SwiftUI Shape — rounded rect + triangular arrow at bottom
- Arrow points at dock icon (X position calculated from mouse position)
- Panel positioned at `screen.origin.y + 75` (dock height)
- `VisualEffectBackground`: NSVisualEffectView with `.hudWindow` material
- Dismissed on click outside (global mouse monitor) or Escape (key monitor)

### Swipe/scroll handling

Trackpad swipe navigates one page at a time. Implemented in two places:

**Popup** (`PopupPanel.scrollWheel`):
- Overrides `scrollWheel(with:)` directly in NSPanel (global monitors don't capture events in nonactivatingPanel)
- Tracks `event.phase` (.began/.ended/.cancelled) and `momentumPhase`
- Triggers once per gesture, ignores momentum

**Main app** (`ScrollWheelOverlay` in `FolderDetailView`):
- NSViewRepresentable wrapping an NSView with `scrollWheel` override
- Same logic: one page per gesture via phase tracking

### Icon generation (`IconGenerator.swift`)

- 1024x1024 canvas with ~10% inset (transparent padding around the icon)
- Rounded rect background (dark/light mode aware, 0.85/0.75 alpha)
- macOS-matching corner radius (22.37%)
- Subtle border stroke (12px width, low alpha)
- App icons rendered in grid inside background
- Generates icon for both folder directory and launcher .app bundle
- `regenerateAllIcons()` updates all folders

### Auto-update of dock icons

`FolderStore` calls `IconGenerator.generateIcon()` + `DockController.refreshDock()` on:
- `saveGridConfig` — column/items per page change
- `reorderApps` — app order change
- `addApp` / `removeApp` — adding/removing apps
- `renameFolder` — folder rename

Manual "Update Icon" button in GridSettingsBar (spin icon with rubberband animation).

## Build and deploy

### Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DockFolders/DockFolders.xcodeproj \
  -scheme DockFolders -configuration Release build
```

### Export to Applications

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/DockFolders-*/Build/Products/Release/DockFolders.app "/Applications/Imperator Dock Folders.app"
codesign --sign - --force --deep "/Applications/Imperator Dock Folders.app"
```

The app shows as "Imperator Dock Folders" in Finder (via `CFBundleDisplayName`).

### Ad-hoc code signing

Build phase "Code Sign" in the Xcode project runs:
```
codesign --sign - --force --deep "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
```
Without this, Gatekeeper blocks the app as "damaged" when transferred via AirDrop etc.

## Key design decisions

1. **Symlinks, not Finder aliases** — easier to create/manage programmatically
2. **HSplitView instead of NavigationSplitView** — full control over toolbar placement
3. **persistent-apps instead of persistent-others** — folder icons mixed with regular apps
4. **Darwin notifications instead of URL scheme** — works even without running app
5. **Launcher auto-starts the app** — `pgrep` + `open -g -b` in the shell script
6. **Manual Update Icon button** — `applicationWillTerminate` doesn't have time to run icon generation

## TODO v2

### 1. Smoother popup experience
Investigate if the popup panel can open faster/smoother. Currently takes ~0.5s from click to visible popup. Possible improvements:
- Pre-load folder data at app start instead of `store.reload()` on every popup
- Reduce latency in Darwin notification -> panel display
- Faster icon loading (cache NSImage instances)
- Profile `FolderPopupController.show()` to find bottlenecks

### 2. Popup should stay above the folder icon in Dock
Problem: If the user moves the mouse quickly after clicking, the popup appears at the cursor instead of above the folder icon. Cause: mouse position is read in the launcher script, but it takes ~0.5s before the app receives the Darwin notification and shows the panel — during that time the mouse may have moved.

Possible solutions:
- Save mouse position at click time (already done in launcher script via CoreGraphics) — verify this position is actually used and not `NSEvent.mouseLocation` as fallback
- Calculate the dock icon's fixed position instead of using mouse position: read the Dock plist's `persistent-apps` order + dock size/position to calculate exact X coordinate
- Alternative: cache the last click position per folder and reuse if a new position arrives within a short time

Relevant code:
- `LauncherGenerator.swift` line 42-43: script writes mouse position to `/tmp/dockfolders_open`
- `DockFoldersApp.swift` `handleDarwinNotification()`: reads the file and converts coordinates
- `FolderPopupController.show()`: receives `mousePosition` and positions the panel

## Known limitations

- Launcher script uses Python3 for CoreGraphics mouse position capture
- `pgrep -xq DockFolders` matches the process name — if `PRODUCT_NAME` changes, the script must be updated
- Bundle identifier `com.dockfolders.app` is hardcoded in the launcher script
- Dock icon cache may need `killall Dock` / `lsregister` to update
- `main` branch on GitLab is protected — force push requires unprotecting it first

## Conventions

- All UI text in English
- Commit messages in English
- Documentation in English
- Ad-hoc code signing always on build
- No new libraries/patterns — everything built on SwiftUI + AppKit
