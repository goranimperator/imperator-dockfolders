# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Imperator DockFolders

macOS app (Swift/SwiftUI/AppKit) that creates custom app folder shortcuts in the Dock. Minimum macOS 14, no App Sandbox.

This app is part of the Imperator family. Visual + structural rules live in the **Imperator Apps BrandBook** at `https://gitlab.com/goranimperator/imperator-mac-apps-brandbook` — pull and read it before doing any UI work. DockFolders is already aligned: forced dark mode, brand-only red accent (`#A01818` via `AppColors.brand`, never bare `Color.accentColor`), and the standard `AppColors` / `HoverButton` / `PillIconButton` / `ViewExtensions` boilerplate is in place.

## Build, deploy, run

```bash
# Build (Release)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DockFolders/DockFolders.xcodeproj \
  -scheme DockFolders -configuration Release build

# Deploy + restart. Always rm -rf first — plain `cp -R` will not overwrite
# the existing bundle, so the old binary lingers in /Applications.
pkill -x "Imperator DockFolders" 2>/dev/null; sleep 1
rm -rf "/Applications/Imperator DockFolders.app"
cp -R ~/Library/Developer/Xcode/DerivedData/DockFolders-*/Build/Products/Release/"Imperator DockFolders.app" "/Applications/Imperator DockFolders.app"
open "/Applications/Imperator DockFolders.app"
```

The build phase runs `codesign --sign "Imperator Dev" --force --deep` automatically. `PRODUCT_NAME`, `CFBundleDisplayName`, the window title, and the runtime process name (set via `ProcessInfo.processInfo.setValue(...)` in `applicationWillFinishLaunching`) are all `Imperator DockFolders`. The launcher shell script `pgrep`s on that exact name — if you ever rename the product, also patch `LauncherGenerator.swift`.

There are no tests in this project. Verification is manual: build, deploy, restart, click around.

## Architecture

### File system is the source of truth

```
~/Library/Application Support/DockFolders/
  FolderName/
    .gridconfig        JSON {"columns": 3, "itemsPerPage": 9}
    .apporder          JSON ["App1.app", "App2.app", ...]
    .labels            JSON {"Slack.app": "Custom label", ...}
    Safari.app         symlink -> /Applications/Safari.app
    Slack.app          symlink -> /Applications/Slack.app
  .launchers/
    FolderName.app/    generated launcher bundle (custom .icns + shell script)
```

`FolderStore.reload()` rebuilds the in-memory `DockFolder` list from disk; every mutation writes through and reloads. `DockFoldersPath` enum lives inside `FolderStore.swift` and is the only place that knows about file paths or JSON shape.

### Launcher → app IPC

When the user clicks a dock folder icon, the launcher .app's `Contents/MacOS/launcher` shell script runs:

1. A compiled Swift helper `mousepos` captures the mouse position via CoreGraphics.
2. The script writes `folder name + x + y` to `/tmp/dockfolders_open`.
3. Auto-starts the main app if needed: `pgrep -xq "Imperator DockFolders" || open -g -b com.dockfolders.app --args --background`.
4. Posts Darwin notification `com.dockfolders.open` via `notifyutil -p`.
5. `AppDelegate` listens via `CFNotificationCenterGetDarwinNotifyCenter()` and opens the popup at the captured mouse position.

If the bundle identifier `com.dockfolders.app` ever changes, the launcher script template in `LauncherGenerator.swift` must be updated.

`mousepos` is compiled by the **Build mousepos Helper** build phase from `MouseLocation/main.swift`
into `Contents/MacOS/mousepos`, and `LauncherGenerator.ensureMouseposHelper()` copies it out to
`.launchers/mousepos` on every launch. Do not move that compile back to runtime: `/usr/bin/swiftc`
is an xcode-select shim, so on a Mac without developer tools it pops the "Install Command Line
Developer Tools" dialog at the user (`xcode-select: note: No developer tools were found, requesting install.`).

### Dock integration

`DockController.swift` writes launcher .app bundles into `com.apple.dock`'s `persistent-apps` (not `persistent-others`) so they appear among regular apps. Direct plist read/write via `CFPreferences` + `killall Dock` to apply. URL variants with spaces and `%20` encoding are normalized when matching existing entries.

### Popup panel

`FolderPopupPanel.swift` is a custom `NSPanel` subclass (`PopupPanel`, level `.popUpMenu`, style `.borderless | .nonactivatingPanel`). The custom `PopupShape` draws the rounded body plus a 12pt arrow at the bottom; arrow X comes from `DockIconLocator` (Accessibility API) with mouse-position fallback. Background is `NSVisualEffectView` with `.hudWindow` material — locked to that material per BrandBook 6.3; experiments with `.popover` / `.thinMaterial` were rejected.

- Dismissal: global `NSEvent` mouse-down monitor + local Escape-key monitor.
- App cell width is hard-coded to 88pt across the grid so layout stays aligned even when the "Cut app names" setting truncates names — that toggle only changes line count, never cell size. Empty placeholder cells must use the same width.
- Custom app labels always render in full (2 lines) regardless of cut mode.

### Swipe / scroll handling

Trackpad swipe navigates one page per gesture. Two implementations because event delivery differs:

- **In the popup**: `PopupPanel.scrollWheel(with:)` override. Global monitors don't fire inside non-activating panels.
- **In the main app**: `ScrollWheelOverlay` (an `NSViewRepresentable` around an `NSView` that overrides `scrollWheel`) inside `AppGridCarousel`.

Both track `event.phase` + `momentumPhase`, fire once per gesture, and require horizontal delta to exceed vertical before registering as a page swipe.

### Icon generation

`IconGenerator.generateIcon(for:)` renders a 1024×1024 folder icon: rounded-rect background (macOS-matching 22.37% corner radius, alpha-tuned for dark mode), subtle border stroke, and the grid of app icons inside. Writes the same icon both to the folder directory and the launcher .app bundle. `regenerateAllIcons()` reruns for every folder.

`FolderStore` triggers `IconGenerator.generateIcon(for:)` + `DockController.refreshDock()` on every mutation (`saveGridConfig`, `reorderApps`, `addApp`/`removeApp`, `renameFolder`). `applicationWillTerminate` does not have time to run icon generation, so a manual "Update Icon" button is also exposed in `GridSettingsBar` for cases where regeneration was missed.

### macOS Sequoia / Cryptex symlinks

System apps like Safari, Mail, and Maps live behind Cryptex symlinks on macOS 15+. URL-based `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)` silently skips these. `AppDiscovery.swift` uses the string-based `contentsOfDirectory(atPath:)` API instead, and `AppEntry.cachedIcon` + `AppPickerView.PickerApp.init` both call `.resolvingSymlinksInPath()` before reading the icon so Cryptex-mounted apps return the correct appearance-aware artwork. See BrandBook section 22.

## Inline editing pattern (double-click to rename)

Folder name in the sidebar, folder name in the detail header, and per-app label in the grid all use the same flow:

- `Text(...)` with `.onTapGesture(count: 2)` enters edit mode.
- A `TextField` is shown with `@FocusState`, `.onExitCommand`, and an `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` click-outside monitor installed only while editing.
- The monitor hit-tests the click against the focused field via `window.firstResponder` so clicks inside the field don't immediately resign focus.

Canonical implementation: `FolderDetailView.installClickOutsideMonitor()`. Mirror this rather than reinventing — `.background { Color.clear.onTapGesture {...} }` looks like it should work but is blocked by child interactive content.

## Code signing certificate (one-time per Mac)

The app uses a self-signed cert "Imperator Dev" — not ad-hoc — so macOS persists Accessibility (TCC) permissions across rebuilds and machine transfers. Create it once:

```bash
cat > /tmp/cert.conf <<'CONF'
[ req ]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_code
[ dn ]
CN = Imperator Dev
O = Imperator
[ v3_code ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:false
CONF

openssl req -x509 -newkey rsa:2048 -keyout /tmp/cert-key.pem -out /tmp/cert.pem -days 3650 -nodes -config /tmp/cert.conf
openssl pkcs12 -export -out /tmp/cert.p12 -inkey /tmp/cert-key.pem -in /tmp/cert.pem -passout pass:temp123 -legacy
security import /tmp/cert.p12 -k ~/Library/Keychains/login.keychain-db -P temp123 -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/cert.pem
security find-identity -v -p codesigning   # should show "Imperator Dev"
```

To install on another Mac: import the `.p12`, unzip the built `.app` into `/Applications/`, `xattr -cr` to clear quarantine, `open`, then grant Accessibility on first prompt.

## Conventions

- All UI text, documentation, and commit messages in English. Swedish is fine in conversation but never ends up in committed content.
- Never use bare `Color.accentColor` — always `AppColors.brand` (BrandBook 14.2). Same for inlined `Color(red: 0xa0/255, ...)`; route everything through the enum.
- Symlinks, not Finder aliases — created via `FileManager.createSymbolicLink`.
- `HSplitView`, not `NavigationSplitView` — needed for explicit toolbar control.
- Darwin notifications, not URL schemes — the launcher must work when the main app is not running.
- No new third-party libraries — SwiftUI + AppKit only.

## Known limitations

- Bundle identifier `com.dockfolders.app` and product name `Imperator DockFolders` are hard-coded in the launcher shell script template in `LauncherGenerator.swift`.
- Dock icon cache occasionally needs a manual `killall Dock` / `lsregister` to refresh after a major change.
- App is arm64-only. `xcodebuild` builds for the host arch; a universal build needs `ARCHS="arm64 x86_64"` (the mousepos build phase already loops over `ARCHS`).

## Release

`origin` is GitHub: `git@github.com:goranimperator/imperator-dockfolders.git`. Releases are cut
with the `imperator-release` skill — audit first, tag and publish last, never without Goran's
explicit word. Version lives in `MARKETING_VERSION` in `project.pbxproj`; `CURRENT_PROJECT_VERSION`
should be set from `git rev-list --count HEAD` at release time.

## Open task

**Optimize folder popup panel load time.** The popup is currently slow on first click. Investigate `NSHostingView.fittingSize` measurement pass, AX `DockIconLocator.iconCenter` lookup, `.hudWindow` material warm-up, and `AppEntry.icon` cache miss. Candidates: pre-warm/pre-create the hosting view at app launch, cache the measured size per (folder, columns, perPage) tuple, pre-load icons.
