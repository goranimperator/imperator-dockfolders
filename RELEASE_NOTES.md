Performance and reliability release. No new features, no changed behavior — the same app, much faster.

- Click-to-popup is now ~15ms when Accessibility is granted (was ~150ms): the app reacts to the
  Dock click directly instead of waiting for macOS to spawn the launcher. Without Accessibility
  the launcher path serves every click at ~100ms, still faster than 1.0.0.
- The first click after login opens the popup reliably in under 400ms. In 1.0.0 it took over a
  second and sometimes did nothing.
- Fixed a bug where a Dock folder tile could turn into a blank white icon after the app updated
  its launchers.
- The launcher no longer needs developer tools on the machine: 1.0.0 could pop the "Install
  Command Line Developer Tools" dialog on Macs without Xcode. The helper now ships prebuilt
  inside the app.

Requires macOS 14 or later, Apple silicon. Built and tested on macOS 26 only — older versions
are expected to work but have not been verified.

Install at your own risk. The app is not notarized and carries no Apple Developer signature, so
macOS cannot vouch for it. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch: right-click the app and choose Open, or run
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`.

Grant Accessibility when prompted — it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
