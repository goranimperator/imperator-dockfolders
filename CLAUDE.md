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
cp -R ~/Library/Developer/Xcode/DerivedData/DockFolders-*/Build/Products/Release/"Imperator Dock Folders.app" "/Applications/Imperator Dock Folders.app"
codesign --sign - --force --deep "/Applications/Imperator Dock Folders.app"
```

`PRODUCT_NAME` is "Imperator Dock Folders" — this controls the menu bar name, System Settings name, and process name.

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

## TODO v3

### 1. Prevent Dock genie effect when moving mouse to popup panel
When clicking a dock folder icon, the Dock may start its genie/bounce animation. Investigate if this can be suppressed or interrupted when the mouse moves toward the popup panel. The launcher `.app` currently has `LSUIElement = true` but the Dock still animates the icon.

### 2. Popup panel visual polish
Update popup styling to better match macOS native feel:
- Arrow shape and size refinement
- Corner radius tuning
- Background material/blur adjustments
- Border stroke styling

## Known limitations

- Launcher script uses compiled Swift helper for CoreGraphics mouse position capture
- `pgrep -xq "Imperator Dock Folders"` matches the process name — if `PRODUCT_NAME` changes, update `LauncherGenerator.swift`
- Bundle identifier `com.dockfolders.app` is hardcoded in the launcher script
- Dock icon cache may need `killall Dock` / `lsregister` to update
- `main` branch on GitLab is protected — force push requires unprotecting it first

## Conventions

- All UI text in English
- Commit messages in English
- Documentation in English
- Ad-hoc code signing always on build
- No new libraries/patterns — everything built on SwiftUI + AppKit
