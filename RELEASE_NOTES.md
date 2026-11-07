The app now tells you when a newer version is out.

- Once a day the app asks GitHub for the latest release. When there is a newer one, a row in the sidebar says so with a Download button, and you get one notification per new version. Both open the release page; installing works as before.
- The check is the app's only network traffic. It sends nothing but the app's name and version. Turn it off, or check right away, in Settings → Updates.
- Updating is still done by hand. A downloaded update is blocked by Gatekeeper on first launch like any download of this app: choose Done and run the `xattr` command below again.
- macOS asks once whether the app may show notifications, the first time there is an update to report. Saying no is fine: the sidebar row still appears.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Builds carry no Apple Developer ID and are not notarized, so macOS cannot vouch for the app.
Install at your own risk. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch with a dialog that offers only Move to Trash and Done: choose
Done. Then clear the quarantine flag once with
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`, after the app is in
`/Applications`, or open System Settings → Privacy & Security and click Open Anyway.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. The only network request is the daily
update check, which sends nothing but the app's name and version.
