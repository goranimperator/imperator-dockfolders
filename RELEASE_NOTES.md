Custom app folders in the macOS Dock: group the apps you use into a folder, put it on the left
side of the Dock among the real apps, and click it for a popup grid with your own order, labels,
and grid size. Apps are added as symlinks, so nothing is copied or moved.

Requires macOS 14 or later, Apple silicon. Built and tested on macOS 26 only — older versions
are expected to work but have not been verified.

Install at your own risk. The app is not notarized and carries no Apple Developer signature, so
macOS cannot vouch for it. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch: right-click the app and choose Open, or run
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`.

Grant Accessibility when prompted so the popup can anchor to the Dock icon. It is optional —
without it the popup falls back to the mouse position. No other permissions are requested, and
the app makes no network requests.
