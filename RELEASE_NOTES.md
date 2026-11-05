Install instructions corrected. The app itself is unchanged from 1.0.6.

The first launch is blocked by Gatekeeper with a dialog that offers only Move to Trash and Done.
Choose Done. The README told you to right-click the app and choose Open, which no longer gets past
it on current macOS. The steps that work now come first: clear the quarantine flag once, or use
Open Anyway in System Settings → Privacy & Security.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Builds carry no Apple Developer ID and are not notarized, so macOS cannot vouch for the app.
Install at your own risk. It is provided as is, with no warranty, under the MIT license.

Clear the quarantine flag with
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`, after the app is in
`/Applications`. Or open System Settings → Privacy & Security, click Open Anyway next to
Imperator DockFolders, and confirm with your password or Touch ID. That line only shows for a
while after a blocked launch, so start the app once first.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
