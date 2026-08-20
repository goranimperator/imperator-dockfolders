Bug-fix release for the folder popup.

- Fixed app labels rendering as garbled, overlapping text when hovering a cell and swiping
  back and forth between pages. Two separate causes: grid cells were identified by their
  position instead of by the app in them, so a fast interrupted swipe could reuse a cell for a
  different app and drag the old label along; and the hover animation applied to the whole
  cell, so a cell sliding under a stationary pointer got its position animated on the hover
  curve while the page animated on its own, which could leave a label behind its icon.
- Paging no longer uses an insertion/removal transition. Pages sit side by side and paging
  animates one offset, so two pages can never occupy the same layout slot.
- A last page with fewer apps is now aligned to the top, so icons sit at the same height on
  every page instead of being centered vertically.
- Hover highlight no longer sticks to an app that has scrolled off the page.

Requires macOS 14 or later, Apple silicon. Built and tested on macOS 26 only — older versions
are expected to work but have not been verified.

Install at your own risk. The app is not notarized and carries no Apple Developer signature, so
macOS cannot vouch for it. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch: right-click the app and choose Open, or run
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`.

Grant Accessibility when prompted — it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
