Arranging apps works like an iPhone home screen, the sidebar reorders the same way, and the popup lands on the right display.

- Hold an app, or click Arrange, and the icons start to wiggle. Drag one and the others move out of its way while you drag, instead of nothing moving until you let go. Hold it at a side edge to turn the page. The red badge that removes an app only shows while arranging. Done, Escape or a click on empty space stops.
- The Dock is no longer restarted for every icon you move. It is refreshed once, when you finish arranging, so the window no longer freezes and the Dock no longer flashes per move.
- A two-finger swipe turns the page wherever the pointer is. It used to work only in the gaps between icons.
- Folders in the sidebar lift and slide into place when dragged, the same way.
- Cut app names, Refresh all folders and Reset app names moved into a Folder options section under Add Folder, closed by default, each with a line explaining what it does.
- With more than one display, the popup measured against the screen with the active window instead of the screen with the Dock. It could open at the wrong height or close on its own. It now uses the Dock's screen. This is fixed in code and tested with one display only.
- Built in Swift 6 language mode. The compiler found one real data race, in redrawing folder icons in the background, and it is fixed.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Builds carry no Apple Developer ID and are not notarized, so macOS cannot vouch for the app.
Install at your own risk. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch with a dialog that offers only Move to Trash and Done: choose
Done. Then clear the quarantine flag once with
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`, after the app is in
`/Applications`, or open System Settings → Privacy & Security and click Open Anyway.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
