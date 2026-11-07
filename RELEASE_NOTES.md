Page the popup by clicking and dragging, page with a mouse wheel, and a pass against the updated Imperator BrandBook.

- The popup pages by clicking and dragging, as well as by trackpad swipe and the page dots. The pages follow the pointer and give at the first and last page, and a quick flick turns the page. A click that does not move still opens the app; a swipe that starts on an icon never does.
- A mouse wheel turns pages, in the popup and in the main window. Before, only a trackpad could.
- An icon dropped in an empty slot at the end of a page row stays on that page. It used to land on the next one.
- Folder rows in the sidebar no longer react to hover. The delete button shows on the selected folder, and long folder names stay on one line.
- The popup has the window corner of macOS 27: 18pt with a continuous curve, and a 12pt arrow.
- Apps in the grid can be moved with Move Left and Move Right from the keyboard and VoiceOver.
- Fixes found in review: a drag started on an icon in the popup followed at half speed and snapped back; a swipe released outside the popup closed it; a swipe released over a Dock tile reopened the popup; a click beside the grid could open an app from the next page; the pointer could stay a hand after opening an app.
- The README now shows the app, and explains the removable-volume question macOS may ask the first time the app reads an external drive.

Requires macOS 14 or later, Apple silicon. Built against the macOS 27 SDK and tested on
macOS 27 only: older versions are expected to work but have not been verified.

Builds carry no Apple Developer ID and are not notarized, so macOS cannot vouch for the app.
Install at your own risk. It is provided as is, with no warranty, under the MIT license.

Gatekeeper blocks the first launch with a dialog that offers only Move to Trash and Done: choose
Done. Then clear the quarantine flag once with
`xattr -dr com.apple.quarantine "/Applications/Imperator DockFolders.app"`, after the app is in
`/Applications`, or open System Settings → Privacy & Security and click Open Anyway.

Grant Accessibility when prompted: it anchors the popup to the Dock icon and enables the fast
click path. It is optional; everything works without it. No other permissions are requested up
front, and the app makes no network requests.
