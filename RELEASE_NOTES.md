Cursor behaviour now matches the rest of macOS.

- Nothing in the app changes the pointer on hover. App tiles in the Dock popup, rows in the app
  picker and the page dots all keep the ordinary arrow, the way Finder and System Settings
  behave. The picker still shows a not-allowed cursor for apps already in the folder, which is
  the one case where the pointer carries real information.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Builds carry no Apple Developer ID and are not notarized, so macOS cannot vouch for the app.
Install at your own risk. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch: right-click the app and choose Open, or clear the quarantine
flag once with `xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
