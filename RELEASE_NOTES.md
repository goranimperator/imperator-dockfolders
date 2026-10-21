Sidebar rework: new row layout, brand-red selection, and a fifth column option.

- Folder rows carry a drag grip, two columns of three dots, in place of the hamburger glyph that
  ran the full width of the column. The folder icon beside it is a drawn outline matching the
  grip's height, and both sit at the same weight as the dock indicator on the right.
- Selecting a row fills it with the Imperator red at a 6pt corner radius and turns everything in
  it white. The list used to tint the system highlight instead, which rendered the red through
  the sidebar material and came out salmon.
- Rows are separated by 8pt, including before the first and after the last, and the selection
  fill keeps the same 8pt clear of the sidebar edges rather than bleeding into them. The grip
  and folder icon line up with the labels in the settings rows above, the dock indicator with
  their toggles.
- Clicking anywhere on a row selects it, including the padding around the labels.
- The sidebar's own title is gone; the window already carries it in the title bar.
- The sidebar toggle is gone from the toolbar. Drag the split to resize instead.
- Open at Login sits in the sidebar footer.
- Per row now offers 5, which pairs with 20 per page for a four-row grid.
- Removing an app shows a white cross on an Imperator red disc.
- Deleting a folder uses a trash icon rather than a cross in a ring.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Builds carry no Apple Developer ID and are not notarized, so macOS cannot vouch for the app.
Install at your own risk. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch: right-click the app and choose Open, or clear the quarantine
flag once with `xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested, and
the app makes no network requests.
