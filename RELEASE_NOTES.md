Apps on external drives can be added, and the menu bar icon is gone.

- The app picker searches mounted external drives as well as the usual application folders. An
  app is found on the drive itself and up to three folders down, which covers a game sitting
  loose on an SSD or inside a launcher's own folder. Only the four fixed application paths were
  searched before, so an app on a drive could not be added at all.
- Settings has an External Drives section: one switch for the whole scan, on by default, and one
  switch per connected drive. A drive you switch off stays off when you unplug it and plug it
  back in.
- Network volumes, the boot volume and Time Machine stores are never walked. A network share can
  take as long as the server wants to answer, and a backup store holds every app of every Mac
  backed up to it.
- Choose Apps in the picker opens a file dialog and reaches an app anywhere: deeper on a drive
  than the scan goes, on a network share, or on a drive left out of the scan.
- The picker searches in the background with a progress indicator instead of freezing while it
  works, and says so when it finds nothing.
- The menu bar icon is gone, along with its Settings switch. The app is reached through its Dock
  folders and its main window.
- Every switch in Settings is brand red again. They had been rendering in the system grey.

An app on a drive that is not connected drops out of its folder until the drive is back, and the
folder icon regenerates without it.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Builds carry no Apple Developer ID and are not notarized, so macOS cannot vouch for the app.
Install at your own risk. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch: right-click the app and choose Open, or clear the quarantine
flag once with `xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
