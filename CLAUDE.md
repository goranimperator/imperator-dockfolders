# Imperator Dock Folders

macOS-app (Swift/SwiftUI/AppKit) som skapar anpassade appmappar i Dock. Minimum macOS 14, ingen App Sandbox.

## Arkitekturöversikt

Appen skapar "folder"-mappar i `~/Library/Application Support/DockFolders/`. Varje mapp innehåller symlinks till appar. När en mapp läggs till i Dock skapas en liten launcher `.app`-bundle som placeras bland vanliga appar i Dockens `persistent-apps`-sektion. Klick på launcher-ikonen triggar en custom popup ovanför Dock (inte macOS inbyggda folder-grid).

### Filsystemet som källa till sanning

```
~/Library/Application Support/DockFolders/
  MappNamn/
    .gridconfig        <- JSON: {"columns": 3, "itemsPerPage": 9}
    .apporder          <- JSON: ["App1.app", "App2.app", ...]
    Safari.app         <- symlink -> /Applications/Safari.app
    Slack.app          <- symlink -> /Applications/Slack.app
  .launchers/
    MappNamn.app/      <- genererad launcher-bundle
```

## Projektstruktur

```
DockFolders/DockFolders/
  DockFoldersApp.swift      <- App entry point, AppDelegate, Darwin-lyssnare
  Info.plist                <- CFBundleIconFile, URL scheme (dockfolders://)
  Models/
    DockFolder.swift        <- DockFolder + GridConfig structs
    AppEntry.swift          <- AppEntry struct (ikon, URL, namn)
    AppearanceMode.swift    <- Enum: system/dark
  Services/
    FolderStore.swift       <- CRUD, grid config, reorder, dock toggle. DockFoldersPath enum.
    DockController.swift    <- Läser/skriver com.apple.dock plist, persistent-apps
    IconGenerator.swift     <- Genererar folder-ikoner (rounded rect + app grid)
    LauncherGenerator.swift <- Skapar launcher .app-bundles med shell-script
    AppDiscovery.swift      <- Söker /Applications + ~/Applications
    AppearanceObserver.swift <- Lyssnar på dark/light mode-ändringar
  Views/
    ContentView.swift       <- HSplitView med sidebar + detail
    FolderListView.swift    <- Sidebar: lista av mappar
    FolderDetailView.swift  <- App-grid med carousel, drag-reorder, grid settings
    FolderPopupPanel.swift  <- Custom NSPanel popup med pil + visuell effekt
    AppPickerView.swift     <- Sheet för att lägga till appar
    MenuBarView.swift       <- MenuBarExtra-vy
    SettingsView.swift      <- Inställningar (theme, menu bar)
    SigilShape.swift        <- Imperator sigil SVG som SwiftUI Shape
  Resources/
    Assets.xcassets/        <- App icon (alla storlekar)
    AppIcon.icns            <- .icns-fil för Finder-visning
```

## Nyckelmekanismer

### IPC: Launcher -> App

1. Launcher-script (`LauncherGenerator.swift`) körs vid Dock-klick
2. Scriptet fångar musposition via CoreGraphics Python-bridge
3. Skriver mappnamn + muskoordinater till `/tmp/dockfolders_open`
4. Om appen inte kör: startar den med `open -g -b com.dockfolders.app --args --background`
5. Skickar Darwin-notification via `notifyutil -p com.dockfolders.open`
6. AppDelegate lyssnar med `CFNotificationCenterGetDarwinNotifyCenter()`
7. Läser `/tmp/dockfolders_open`, öppnar popup vid musposition

### Dock-integration (`DockController.swift`)

- Placerar launchers i `persistent-apps` (inte `persistent-others`)
- Skriver direkt till `com.apple.dock` plist via `defaults write`
- Hanterar URL-varianter med spaces och %20-encoding
- `killall Dock` för att applicera ändringar

### Popup-panel (`FolderPopupPanel.swift`)

- `PopupPanel`: NSPanel-subklass med `canBecomeKey = true`
- `PopupShape`: Custom SwiftUI Shape — rounded rect + triangulär pil nedtill
- Pilen pekar mot dock-ikonen (X-position beräknas från musposition)
- Panel positioneras vid `screen.origin.y + 75` (dockens höjd)
- `VisualEffectBackground`: NSVisualEffectView med `.hudWindow`-material
- Stängs vid klick utanför (global mouse monitor) eller Escape (key monitor)

### Swipe/scroll-hantering

Trackpad-swipe navigerar en sida i taget. Implementerat på två ställen:

**Popup** (`PopupPanel.scrollWheel`):
- Överskrider `scrollWheel(with:)` direkt i NSPanel (globala monitors fångar inte events i nonactivatingPanel)
- Trackar `event.phase` (.began/.ended/.cancelled) och `momentumPhase`
- Trigger en gång per gesture, ignorerar momentum

**Main app** (`ScrollWheelOverlay` i `FolderDetailView`):
- NSViewRepresentable som wrappar en NSView med `scrollWheel`-override
- Samma logik: en sida per gesture via phase-tracking

### Ikon-generering (`IconGenerator.swift`)

- 1024x1024 canvas med 10% inset (transparent padding runt ikonen)
- Rounded rect bakgrund (dark/light mode aware, 0.7/0.6 alpha)
- App-ikoner renderas i grid inuti bakgrunden
- Genererar ikon för både folder-katalogen och launcher .app-bundlen
- `regenerateAllIcons()` uppdaterar alla folders

### Auto-uppdatering av dock-ikoner

`FolderStore` anropar `IconGenerator.generateIcon()` + `DockController.refreshDock()` vid:
- `saveGridConfig` — ändring av kolumner/items per page
- `reorderApps` — ändring av app-ordning
- `addApp` / `removeApp` — lägga till/ta bort appar
- `renameFolder` — byte av mappnamn

Manuell "Update Icon"-knapp finns i GridSettingsBar (↻-ikon).

## Build och deploy

### Bygga

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DockFolders/DockFolders.xcodeproj \
  -scheme DockFolders -configuration Release build
```

### Exportera till Applications

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/DockFolders-*/Build/Products/Release/DockFolders.app /Applications/
codesign --sign - --force --deep /Applications/DockFolders.app
```

Appen visas som "Imperator Dock Folders" i Finder (via `CFBundleDisplayName`).
Filen heter `/Applications/Imperator Dock Folders.app` (manuellt omdöpt).

### Ad-hoc kodsignering

Build phase "Code Sign" i Xcode-projektet kör:
```
codesign --sign - --force --deep "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
```
Utan detta blockerar Gatekeeper appen som "damaged" vid AirDrop etc.

## Viktiga designbeslut

1. **Symlinks, inte Finder aliases** — enklare att skapa/hantera programmatiskt
2. **HSplitView istället för NavigationSplitView** — ger full kontroll över toolbar-placement
3. **persistent-apps istället för persistent-others** — folder-ikoner blandas med vanliga appar
4. **Darwin notifications istället för URL scheme** — fungerar även utan running app
5. **Launcher auto-startar appen** — `pgrep` + `open -g -b` i shell-scriptet
6. **Manuell Update Icon-knapp** — `applicationWillTerminate` hinner inte köra ikongenerering

## TODO v2

### 1. Smidigare popup-upplevelse
Undersök om popup-panelen kan öppnas snabbare/smoothare. Idag tar det ~0.5s från klick till synlig popup. Möjliga förbättringar:
- Pre-loada folder-data vid app-start istället för `store.reload()` vid varje popup
- Minska latensen i Darwin notification → panel-visning
- Snabbare icon-laddning (cacha NSImage-instanser)
- Profilera `FolderPopupController.show()` för att hitta flaskhalsar

### 2. Popup ska stanna ovanför folder-ikonen i Dock
Problem: Om användaren rör musen snabbt efter klick hamnar popup vid muspekaren istället för ovanför folder-ikonen. Orsak: musposition läses i launcher-scriptet, men det tar ~0.5s innan appen tar emot Darwin-notifikationen och visar panelen — under den tiden kan musen ha flyttats.

Möjliga lösningar:
- Spara musposition vid klick-tillfället (redan görs i launcher-scriptet via CoreGraphics) — verifiera att denna position verkligen används och inte `NSEvent.mouseLocation` som fallback
- Beräkna dock-ikonens fasta position istället för att använda musposition: läs Dock-plistens `persistent-apps` ordning + dockens storlek/position för att beräkna exakt X-koordinat
- Alternativt: cacha senaste klickposition per folder och återanvänd om ny position kommer inom kort tid

Relevant kod:
- `LauncherGenerator.swift` rad 42-43: scriptet skriver musposition till `/tmp/dockfolders_open`
- `DockFoldersApp.swift` `handleDarwinNotification()`: läser filen och konverterar koordinater
- `FolderPopupController.show()`: tar emot `mousePosition` och positionerar panelen

## Kända begränsningar

- Launcher-scriptet använder Python3 för CoreGraphics muspositions-hämtning
- `pgrep -xq DockFolders` matchar processnamnet — om `PRODUCT_NAME` ändras måste scriptet uppdateras
- Bundle identifier `com.dockfolders.app` är hårdkodad i launcher-scriptet
- Dock icon cache kan behöva `killall Dock` / `lsregister` för att uppdateras
- `main`-branchen på GitLab är skyddad — force push kräver att man avskyddar den först

## Conventions

- All UI-text på engelska
- Commit messages på engelska
- Kod-kommentarer och dokumentation på svenska
- Ad-hoc kodsignering alltid vid build
- Inga nya bibliotek/mönster — allt bygger på SwiftUI + AppKit
