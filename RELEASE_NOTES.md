Built against the macOS 27 SDK, with the interface brought in line with it.

- Every control now draws in its current macOS generation. AppKit picks a control's look from
  the SDK recorded in the binary, not from the macOS it runs on, so the previous build drew
  older-looking switches on any system. The minimum is unchanged: the app still runs on
  macOS 14 and later.
- Toggles match the system switch: brand red when on, an oval knob sitting inside the track,
  and the ordinary arrow cursor when you hover them, the way System Settings behaves.
- The sidebar settings controls line up on a shared right edge. The switch used to sit about
  12pt short of the buttons above and below it.
- Open at Login moved into the sidebar footer as well, matching Imperator MenuBarFolders.
- Cut app names and Refresh all folders swapped places.
- Clickable things that are not buttons (app tiles in the popup, rows in the app picker, page
  dots) show the pointing-hand cursor; the picker shows a not-allowed cursor for apps already
  in the folder.
- The popup corner radius is 18pt, matching the window shape macOS 27 draws.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Install at your own risk. The app is not notarized and carries no Apple Developer signature, so
macOS cannot vouch for it. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch: right-click the app and choose Open, or run
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
