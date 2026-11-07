import SwiftUI
import UniformTypeIdentifiers

struct FolderDetailView: View {
    let folder: DockFolder
    @Binding var selectedFolder: DockFolder?
    @Environment(FolderStore.self) private var store
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var showAppPicker = false
    @State private var clickOutsideMonitor: Any?
    @FocusState private var isNameFieldFocused: Bool
    @State private var isArranging = false
    /// The folder whose order or contents changed while arranging. Its Dock icon
    /// is regenerated once, when arranging ends, rather than on every change:
    /// refreshing restarts the whole Dock.
    @State private var unsettledFolderURL: URL?

    private var labels: [String: String] {
        DockFoldersPath.loadLabels(in: folder.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            Divider()

            GridSettingsBar(folder: folder)
            Divider()

            if folder.apps.isEmpty {
                emptyState
            } else {
                AppGridCarousel(
                    apps: folder.apps,
                    columns: folder.gridConfig.columns,
                    itemsPerPage: folder.gridConfig.itemsPerPage,
                    labels: labels,
                    isArranging: $isArranging,
                    onRemove: { app in
                        try? store.removeApp(from: folder, app: app, refreshDock: !isArranging)
                        if isArranging { unsettledFolderURL = folder.url }
                    },
                    onReorder: { newOrder in
                        store.reorderApps(in: folder, to: newOrder, refreshDock: !isArranging)
                        if isArranging { unsettledFolderURL = folder.url }
                    },
                    onSetLabel: { app, label in
                        store.saveLabel(for: folder, appFilename: app.localURL.lastPathComponent, label: label)
                    }
                )
                // One carousel per folder, so switching folders starts on page one
                // instead of animating the last folder's icons into this one's.
                .id(folder.url)
            }
        }
        .onChange(of: isArranging) { _, arranging in
            if !arranging { settleDockIcon() }
        }
        .onChange(of: folder.url) { _, _ in
            isArranging = false
            settleDockIcon()
        }
        .onChange(of: folder.apps.isEmpty) { _, empty in
            if empty { isArranging = false }
        }
        .onDisappear { settleDockIcon() }
        .onChange(of: isNameFieldFocused) { _, focused in
            if !focused && isEditing { commitRename() }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                installClickOutsideMonitor()
            } else {
                removeClickOutsideMonitor()
            }
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(folder: folder)
        }
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window else { return event }
            let locationInWindow = event.locationInWindow
            if let responder = window.firstResponder as? NSView {
                let frameInWindow = responder.convert(responder.bounds, to: nil)
                if frameInWindow.contains(locationInWindow) {
                    return event
                }
            }
            window.makeFirstResponder(nil)
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
    }

    private var header: some View {
        HStack {
            if isEditing {
                TextField("Folder name", text: $editedName, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
                    .focused($isNameFieldFocused)
                    .onExitCommand { commitRename() }
            } else {
                Text(folder.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .onTapGesture(count: 2) {
                        editedName = folder.name
                        isEditing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isNameFieldFocused = true
                        }
                    }
            }

            Spacer()

            if !folder.apps.isEmpty {
                if isArranging {
                    // The one red control on screen while arranging, so the way
                    // out is never in doubt.
                    Button(action: { withAnimation(.easeOut(duration: 0.2)) { isArranging = false } }) {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(minWidth: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.brand)
                    .help("Stop arranging (Esc)")
                } else {
                    Button(action: { withAnimation(.easeOut(duration: 0.2)) { isArranging = true } }) {
                        Label("Arrange", systemImage: "square.grid.3x3")
                    }
                    .help("Move and remove apps. You can also hold an app to start.")
                }
            }

            Button(action: { showAppPicker = true }) {
                Label("Add Apps", systemImage: "plus.app")
            }

            Button(action: { store.toggleDock(for: folder) }) {
                Label(
                    folder.isInDock ? "Remove from Dock" : "Add to Dock",
                    systemImage: folder.isInDock ? "minus.circle" : "dock.rectangle"
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "app.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No apps yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Add Apps") { showAppPicker = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != folder.name {
            try? store.renameFolder(folder, to: trimmed)
            selectedFolder = store.folders.first { $0.name == trimmed }
        }
        isEditing = false
    }

    private func settleDockIcon() {
        guard let url = unsettledFolderURL else { return }
        unsettledFolderURL = nil
        store.refreshDockIcon(forFolderAt: url)
    }
}

struct GridSettingsBar: View {
    let folder: DockFolder
    @Environment(FolderStore.self) private var store
    @State private var resetLabelsHovered = false

    private let columnOptions = [2, 3, 4, 5]
    // 20 fills a four-column grid five rows deep.
    private let pageOptions = [4, 6, 8, 9, 12, 16, 20]

    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Text("Per row")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { folder.gridConfig.columns },
                    set: { newVal in
                        var config = folder.gridConfig
                        config.columns = newVal
                        store.saveGridConfig(for: folder, config: config)
                    }
                )) {
                    ForEach(columnOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .frame(width: 60)
            }

            HStack(spacing: 6) {
                Text("Per page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { folder.gridConfig.itemsPerPage },
                    set: { newVal in
                        var config = folder.gridConfig
                        config.itemsPerPage = newVal
                        store.saveGridConfig(for: folder, config: config)
                    }
                )) {
                    ForEach(pageOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .frame(width: 60)
            }

            Spacer()

            if hasCustomLabels {
                Button(action: {
                    store.resetAllLabels(for: folder)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                        Text("Reset labels")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .opacity(resetLabelsHovered ? 1.0 : 0.4)
                }
                .buttonStyle(.borderless)
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        resetLabelsHovered = h
                    }
                }
            }

            gridPreview
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var hasCustomLabels: Bool {
        !DockFoldersPath.loadLabels(in: folder.url).isEmpty
    }

    private var gridPreview: some View {
        let cols = folder.gridConfig.columns
        let rows = Int(ceil(Double(folder.gridConfig.itemsPerPage) / Double(cols)))
        return VStack(spacing: 1.5) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 1.5) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < folder.gridConfig.itemsPerPage ? AppColors.brand.opacity(0.5) : Color.secondary.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

/// The two decisions a click-and-drag page swipe makes, shared by the main
/// grid and the Dock popup so they feel the same.
enum PageSwipe {
    /// How far the pages follow the pointer. Past the first or last page they
    /// follow at a third of the distance, so they give without pretending
    /// there is more.
    static func follow(_ translation: CGFloat, page: Int, pageCount: Int) -> CGFloat {
        let pastStart = page == 0 && translation > 0
        let pastEnd = page >= pageCount - 1 && translation < 0
        return pastStart || pastEnd ? translation / 3 : translation
    }

    /// The page a released swipe settles on: a fifth of a page's width turns
    /// it, and a quick flick turns it even if it did not travel that far.
    static func target(from page: Int, pageCount: Int, release value: DragGesture.Value, width: CGFloat) -> Int {
        let threshold = width * 0.2
        let travel = abs(value.predictedEndTranslation.width) > abs(value.translation.width)
            ? value.predictedEndTranslation.width
            : value.translation.width
        if travel < -threshold && page < pageCount - 1 { return page + 1 }
        if travel > threshold && page > 0 { return page - 1 }
        return page
    }
}

/// Turns a scroll into one page change per gesture, from a trackpad or a mouse.
///
/// The two differ enough to need separate rules. A trackpad reports a gesture:
/// `.began` starts it, a momentum tail follows it, and both axes carry precise
/// deltas, so a page turn is a horizontal swipe and vertical scrolling is left
/// alone. A plain mouse wheel reports none of that: no phase, no momentum, and
/// on most mice no horizontal axis at all. Held to the trackpad rules it could
/// never turn a page. Ported from Imperator MenuBarFolders.
struct PageSwipeAccumulator {
    /// Far enough that a diagonal two-finger scroll never turns a page.
    private static let trackpadThreshold: CGFloat = 10
    /// One detent. Each wheel event counts as at least one (see `detents`), and
    /// the latch below keeps a fast spin to one page.
    private static let wheelThreshold: CGFloat = 1
    /// A wheel gesture has no end, so a pause ends it instead. Below this,
    /// spinning the wheel keeps adding to the same gesture and turns one page.
    private static let wheelGap: TimeInterval = 0.25

    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var triggered = false
    private var lastWheelTime: TimeInterval = -1

    /// Returns -1 for a page back, 1 for a page forward, 0 for nothing yet.
    mutating func direction(for event: NSEvent) -> Int {
        // Only a real gesture has phases. Precise deltas alone are not enough:
        // wheel smoothers (Mos, remote desktops) send precise deltas with no
        // phase, and under the trackpad rules nothing ever reset them.
        if event.phase != [] || event.momentumPhase != [] {
            return trackpadDirection(for: event)
        }
        return wheelDirection(for: event)
    }

    /// A wheel event as whole detents, never less than one. With the default
    /// scroll acceleration a slow notch reports about 0.1, so raw deltas never
    /// reached a threshold notch by notch.
    private static func detents(_ value: CGFloat) -> CGFloat {
        if value == 0 { return 0 }
        return value > 0 ? max(1, value) : min(-1, value)
    }

    private mutating func trackpadDirection(for event: NSEvent) -> Int {
        if event.phase == .began { reset() }
        if event.phase == .cancelled || event.phase == .ended {
            reset()
            return 0
        }
        // The momentum tail is one gesture's leftovers, not a new swipe.
        if event.momentumPhase != [] { return 0 }
        guard !triggered else { return 0 }
        x += event.scrollingDeltaX
        y += event.scrollingDeltaY
        guard abs(x) > abs(y), abs(x) > Self.trackpadThreshold else { return 0 }
        triggered = true
        return x > 0 ? -1 : 1
    }

    private mutating func wheelDirection(for event: NSEvent) -> Int {
        if lastWheelTime < 0 || event.timestamp - lastWheelTime > Self.wheelGap { reset() }
        lastWheelTime = event.timestamp
        guard !triggered else { return 0 }
        x += Self.detents(event.scrollingDeltaX)
        y += Self.detents(event.scrollingDeltaY)
        // Whichever axis the wheel actually moves: a plain wheel only has Y.
        let delta = abs(x) >= abs(y) ? x : y
        guard abs(delta) >= Self.wheelThreshold else { return 0 }
        triggered = true
        // Up or left goes back, the same way a swipe of that sign does.
        // NSEvent has already applied the natural-scrolling preference.
        return delta > 0 ? -1 : 1
    }

    mutating func reset() {
        x = 0
        y = 0
        triggered = false
    }
}

/// Delivers trackpad scrolls over the grid, wherever the pointer is on it.
///
/// It used to override `scrollWheel(with:)` from behind the grid, which only
/// ever saw a scroll in the gaps between icons: over an icon, SwiftUI's own
/// view takes the event and an unused scroll travels up the superview chain,
/// never sideways to this view. So a two-finger swipe started over an app did
/// nothing. A local monitor sees every scroll in the window first, and this
/// view only decides whether the pointer is over its own bounds. It returns nil
/// from hit testing, so it never takes a click.
class ScrollWheelNSView: NSView {
    var onScrollEvent: ((NSEvent) -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.onScrollEvent?(event)
            }
            return event
        }
    }
}

struct ScrollWheelOverlay: NSViewRepresentable {
    let onScrollEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScrollEvent = onScrollEvent
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScrollEvent = onScrollEvent
    }
}

/// The folder's apps as a paged grid, arranged the way an iPhone home screen is.
///
/// Hold an app (or press Arrange) and the grid starts arranging: every icon
/// wiggles and shows its remove badge. Drag an icon and it lifts out from under
/// the pointer while the others slide out of its way as it moves, so the drop
/// only confirms what is already on screen. Holding it at a side edge turns the
/// page. Done, Escape or a click on empty space stops arranging.
///
/// The drag is a plain gesture over a hand-placed layout rather than
/// onDrag/onDrop. A system drag session floats a translucent snapshot over the
/// window and moves nothing until the drop, which is what made the grid feel
/// broken: the icon you grabbed faded in place and its neighbours never moved.
struct AppGridCarousel: View {
    let apps: [AppEntry]
    let columns: Int
    let itemsPerPage: Int
    let labels: [String: String]
    @Binding var isArranging: Bool
    let onRemove: (AppEntry) -> Void
    let onReorder: ([AppEntry]) -> Void
    let onSetLabel: (AppEntry, String?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentPage: Int = 0
    @State private var pageDragOffset: CGFloat = 0
    @State private var editingAppId: String?
    @State private var editingText: String = ""
    @State private var clickOutsideMonitor: Any?
    @FocusState private var isLabelFieldFocused: Bool
    @State private var swipe = PageSwipeAccumulator()

    /// Display order as app ids. Follows `apps`, except while an icon is lifted,
    /// when it is the live order the other icons slide into.
    @State private var order: [String] = []
    @State private var press: Press?
    @State private var lifted: Lifted?
    @State private var longPressTask: Task<Void, Never>?
    @State private var edgeTask: Task<Void, Never>?
    @State private var edgeDirection = 0
    @State private var keyMonitor: Any?

    private static let space = "appGrid"
    /// Icons settling into slots: quick, with a little give at the end.
    private static let settle = Animation.spring(response: 0.32, dampingFraction: 0.8)
    private static let pageTurn = Animation.interactiveSpring(response: 0.35, dampingFraction: 0.86)
    /// Long enough that a click or a swipe never lifts an icon by accident.
    private static let holdToLift: Duration = .milliseconds(380)
    /// How long an icon has to rest at a side edge before the page turns.
    private static let edgeDwell: Duration = .milliseconds(550)
    private static let edgeWidth: CGFloat = 36

    /// One pointer interaction on an icon, from mouse-down to mouse-up.
    private struct Press {
        enum Phase {
            /// Not arranging, not moved yet: becomes a lift if held, a page swipe if dragged.
            case waiting
            case swiping
            /// Arranging, not moved yet: becomes a lift on the first move.
            case armed
            case lifted
        }
        let id: String
        var phase: Phase
        var location: CGPoint
    }

    private struct Lifted {
        let id: String
        var location: CGPoint
        /// Pointer minus icon centre at the moment of lifting, so the icon stays
        /// where it was grabbed instead of jumping to centre on the pointer.
        let grab: CGSize
        let startOrder: [String]
    }

    private struct Metrics {
        static let spacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 24

        let size: CGSize
        let columns: Int
        let itemsPerPage: Int
        let rows: Int
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let top: CGFloat

        init(size: CGSize, columns: Int, itemsPerPage: Int) {
            self.size = size
            self.columns = columns
            self.itemsPerPage = max(1, itemsPerPage)
            rows = Int(ceil(Double(itemsPerPage) / Double(columns)))
            let availableWidth = size.width - Self.horizontalPadding * 2 - Self.spacing * CGFloat(columns - 1)
            let availableHeight = size.height - 24 - Self.spacing * CGFloat(rows - 1)
            cellWidth = availableWidth / CGFloat(columns)
            cellHeight = min(availableHeight / CGFloat(rows), cellWidth * 1.2)
            // Centred vertically, as the stacked grid this replaces was.
            let gridHeight = cellHeight * CGFloat(rows) + Self.spacing * CGFloat(rows - 1)
            top = (size.height - gridHeight) / 2
        }

        func center(ofSlot slot: Int) -> CGPoint {
            let col = slot % columns
            let row = slot / columns
            return CGPoint(
                x: Self.horizontalPadding + CGFloat(col) * (cellWidth + Self.spacing) + cellWidth / 2,
                y: top + CGFloat(row) * (cellHeight + Self.spacing) + cellHeight / 2
            )
        }

        func slot(nearest point: CGPoint) -> Int {
            let col = Int(((point.x - Self.horizontalPadding) / (cellWidth + Self.spacing)).rounded(.down))
            let row = Int(((point.y - top) / (cellHeight + Self.spacing)).rounded(.down))
            let raw = min(max(row, 0), rows - 1) * columns + min(max(col, 0), columns - 1)
            // A page's rows can hold more slots than the page does: 4 per row
            // and 9 per page is 3 rows, 12 slots for 9 apps. A drop in one of
            // the 3 empty slots named an index on the next page, so the icon
            // jumped off the page it was dropped on.
            return min(raw, itemsPerPage - 1)
        }
    }

    private var orderedApps: [AppEntry] {
        let byId = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [AppEntry] = []
        for id in order {
            if let app = byId[id], seen.insert(id).inserted { result.append(app) }
        }
        for app in apps where seen.insert(app.id).inserted { result.append(app) }
        return result
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(max(order.count, apps.count)) / Double(itemsPerPage))))
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let metrics = Metrics(size: geo.size, columns: columns, itemsPerPage: itemsPerPage)
                ZStack(alignment: .topLeading) {
                    // The empty grid behaves like the wallpaper on an iPhone:
                    // swiping it turns the page, clicking it stops arranging.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isArranging { endArranging() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { value in
                                    pageDragOffset = rubberBanded(value.translation.width, width: geo.size.width)
                                }
                                .onEnded { value in
                                    finishPageSwipe(value, width: geo.size.width)
                                }
                        )

                    ForEach(orderedApps) { app in
                        appCell(app, metrics: metrics)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .coordinateSpace(name: Self.space)
                .clipped()
                .background(
                    ScrollWheelOverlay { event in
                        // A held or carried icon owns paging: the edge dwell
                        // turns pages for it and re-targets the drop.
                        guard press == nil, lifted == nil else { return }
                        let step = swipe.direction(for: event)
                        guard step != 0 else { return }
                        // Clamped rather than range-checked, so a page left
                        // past the end by a smaller Per page still steps back.
                        let target = min(max(currentPage + step, 0), totalPages - 1)
                        guard target != currentPage else { return }
                        withAnimation(Self.pageTurn) { currentPage = target }
                    }
                )
            }

            if totalPages > 1 {
                pageIndicator
                    .padding(.vertical, 12)
            }
        }
        .onAppear { order = apps.map(\.id) }
        .onChange(of: apps.map(\.id)) { _, ids in
            // Adding, removing or committing a reorder lands here. While an icon
            // is lifted the live order is the source of truth.
            guard lifted == nil, ids != order else { return }
            withAnimation(Self.settle) { order = ids }
            currentPage = min(currentPage, totalPages - 1)
        }
        .onChange(of: itemsPerPage) { _, _ in
            // The carousel keeps its state when only Per page changes, so a
            // page past the new end has to be pulled back.
            currentPage = min(currentPage, totalPages - 1)
        }
        .onChange(of: isArranging) { _, arranging in
            if arranging {
                installKeyMonitor()
            } else {
                stopInteraction()
                removeKeyMonitor()
            }
        }
        .onDisappear {
            stopInteraction()
            removeKeyMonitor()
            removeClickOutsideMonitor()
        }
        .onChange(of: isLabelFieldFocused) { _, focused in
            if !focused, let appId = editingAppId {
                if let app = apps.first(where: { $0.id == appId }) {
                    let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSetLabel(app, trimmed.isEmpty || trimmed == app.name ? nil : trimmed)
                }
                editingAppId = nil
            }
        }
        .onChange(of: editingAppId) { _, appId in
            if appId != nil {
                installClickOutsideMonitor()
            } else {
                removeClickOutsideMonitor()
            }
        }
    }

    // MARK: - Cells

    private func appCell(_ app: AppEntry, metrics: Metrics) -> some View {
        let isLifted = lifted?.id == app.id
        return cellContent(app, metrics: metrics, isLifted: isLifted)
            .modifier(Wiggle(active: isArranging && !isLifted && !reduceMotion, seed: app.id))
            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
            .contentShape(Rectangle())
            .scaleEffect(isLifted ? 1.15 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.45 : 0), radius: isLifted ? 14 : 0, y: isLifted ? 8 : 0)
            .position(position(of: app, metrics: metrics))
            .zIndex(isLifted ? 1 : 0)
            // Animates the lift and, on release, the glide from the pointer into
            // the slot. While the icon is held it tracks the pointer unanimated.
            .animation(Self.settle, value: isLifted)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in pointerChanged(on: app, value, metrics: metrics) }
                    .onEnded { value in pointerEnded(on: app, value, metrics: metrics) },
                including: editingAppId == app.id ? .subviews : .all
            )
            .accessibilityAction(named: "Move Left") { step(app, by: -1) }
            .accessibilityAction(named: "Move Right") { step(app, by: 1) }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    /// Keyboard and VoiceOver path for reordering: one slot at a time, committed
    /// straight away (BrandBook 7.18).
    ///
    /// It enters arranging first, as a drag does, so the Dock icon is redrawn
    /// once at Done rather than with a Dock restart per step, and it follows the
    /// app onto its new page.
    private func step(_ app: AppEntry, by offset: Int) {
        guard lifted == nil, press == nil, let from = order.firstIndex(of: app.id) else { return }
        let to = min(max(from + offset, 0), order.count - 1)
        guard to != from else { return }
        if !isArranging {
            withAnimation(.easeOut(duration: 0.2)) { isArranging = true }
        }
        withAnimation(Self.settle) {
            order.remove(at: from)
            order.insert(app.id, at: to)
        }
        withAnimation(Self.pageTurn) { currentPage = to / itemsPerPage }
        commitOrder()
    }

    private func commitOrder() {
        let byId = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        onReorder(order.compactMap { byId[$0] })
    }

    private func cellContent(_ app: AppEntry, metrics: Metrics, isLifted: Bool) -> some View {
        let iconSize = min(metrics.cellWidth * 0.55, metrics.cellHeight * 0.55)
        let filename = app.localURL.lastPathComponent
        let customLabel = labels[filename]
        let displayName = customLabel ?? app.name

        return VStack(spacing: 4) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .overlay(alignment: .topTrailing) {
                    if isArranging && !isLifted {
                        DeleteBadge { remove(app) }
                            .offset(x: 4, y: -4)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }

            Group {
                if editingAppId == app.id {
                    TextField("Label", text: $editingText, onCommit: {
                        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSetLabel(app, trimmed.isEmpty || trimmed == app.name ? nil : trimmed)
                        editingAppId = nil
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: metrics.cellWidth - 4)
                    .focused($isLabelFieldFocused)
                } else {
                    HStack(spacing: 10) {
                        Text(displayName)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                editingText = displayName
                                editingAppId = app.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isLabelFieldFocused = true
                                }
                            }

                        if customLabel != nil {
                            RevertLabelButton {
                                onSetLabel(app, nil)
                            }
                        }
                    }
                    .frame(maxWidth: metrics.cellWidth - 4)
                }

                if !app.exists {
                    Text("Missing")
                        .font(.caption2)
                        .foregroundStyle(AppColors.error)
                }
            }
            // The label stays behind while the icon is carried, as on an iPhone.
            .opacity(isLifted ? 0 : 1)
        }
    }

    private func position(of app: AppEntry, metrics: Metrics) -> CGPoint {
        if let lifted, lifted.id == app.id {
            return CGPoint(x: lifted.location.x - lifted.grab.width, y: lifted.location.y - lifted.grab.height)
        }
        let index = order.firstIndex(of: app.id) ?? order.count
        let page = index / itemsPerPage
        var point = metrics.center(ofSlot: index % itemsPerPage)
        point.x += CGFloat(page - currentPage) * metrics.size.width + pageDragOffset
        return point
    }

    // MARK: - Pointer

    private func pointerChanged(on app: AppEntry, _ value: DragGesture.Value, metrics: Metrics) {
        if press?.id != app.id {
            press = Press(id: app.id, phase: isArranging ? .armed : .waiting, location: value.location)
            if !isArranging { scheduleLift(of: app, metrics: metrics) }
        }
        guard var current = press else { return }
        current.location = value.location
        let moved = hypot(value.translation.width, value.translation.height)

        switch current.phase {
        case .waiting:
            if moved > 6 {
                cancelScheduledLift()
                current.phase = .swiping
                pageDragOffset = rubberBanded(value.translation.width, width: metrics.size.width)
            }
        case .swiping:
            pageDragOffset = rubberBanded(value.translation.width, width: metrics.size.width)
        case .armed:
            if moved > 3 {
                current.phase = .lifted
                lift(app, at: value.startLocation, metrics: metrics)
                moveLifted(to: value.location, metrics: metrics)
            }
        case .lifted:
            moveLifted(to: value.location, metrics: metrics)
        }
        press = current
    }

    private func pointerEnded(on app: AppEntry, _ value: DragGesture.Value, metrics: Metrics) {
        cancelScheduledLift()
        guard let current = press, current.id == app.id else {
            press = nil
            return
        }
        press = nil
        switch current.phase {
        case .swiping:
            finishPageSwipe(value, width: metrics.size.width)
        case .lifted:
            drop()
        case .waiting, .armed:
            break
        }
    }

    /// Holding an app without moving starts arranging and picks that app up in
    /// the same motion, so the drag that follows moves it.
    private func scheduleLift(of app: AppEntry, metrics: Metrics) {
        cancelScheduledLift()
        longPressTask = Task { @MainActor in
            try? await Task.sleep(for: Self.holdToLift)
            guard !Task.isCancelled, var current = press, current.id == app.id, current.phase == .waiting else { return }
            withAnimation(.easeOut(duration: 0.2)) { isArranging = true }
            current.phase = .lifted
            press = current
            lift(app, at: current.location, metrics: metrics)
        }
    }

    private func cancelScheduledLift() {
        longPressTask?.cancel()
        longPressTask = nil
    }

    private func lift(_ app: AppEntry, at location: CGPoint, metrics: Metrics) {
        let center = position(of: app, metrics: metrics)
        lifted = Lifted(
            id: app.id,
            location: location,
            grab: CGSize(width: location.x - center.x, height: location.y - center.y),
            startOrder: order
        )
        haptic(.levelChange)
    }

    private func moveLifted(to location: CGPoint, metrics: Metrics) {
        guard var current = lifted else { return }
        current.location = location
        lifted = current

        let center = CGPoint(x: location.x - current.grab.width, y: location.y - current.grab.height)
        let target = min(currentPage * itemsPerPage + metrics.slot(nearest: center), order.count - 1)
        if let from = order.firstIndex(of: current.id), from != target {
            withAnimation(Self.settle) {
                order.remove(at: from)
                order.insert(current.id, at: target)
            }
            haptic(.alignment)
        }
        updateEdgeTurn(iconCenter: center, metrics: metrics)
    }

    /// An icon held at a side edge turns the page after a short rest, and keeps
    /// turning while it stays there.
    private func updateEdgeTurn(iconCenter: CGPoint, metrics: Metrics) {
        let direction: Int
        if iconCenter.x < Self.edgeWidth {
            direction = -1
        } else if iconCenter.x > metrics.size.width - Self.edgeWidth {
            direction = 1
        } else {
            direction = 0
        }

        guard direction != 0, (0..<totalPages).contains(currentPage + direction) else {
            edgeTask?.cancel()
            edgeTask = nil
            edgeDirection = 0
            return
        }
        if edgeTask != nil && edgeDirection == direction { return }

        edgeTask?.cancel()
        edgeDirection = direction
        edgeTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.edgeDwell)
                guard !Task.isCancelled, let current = lifted,
                      (0..<totalPages).contains(currentPage + direction) else { return }
                withAnimation(Self.pageTurn) { currentPage += direction }
                haptic(.generic)
                // Re-target on the new page; the pointer has not moved.
                moveLifted(to: current.location, metrics: metrics)
            }
        }
    }

    private func drop() {
        edgeTask?.cancel()
        edgeTask = nil
        edgeDirection = 0
        guard let current = lifted else { return }
        withAnimation(Self.settle) { lifted = nil }
        if order != current.startOrder { commitOrder() }
    }

    private func remove(_ app: AppEntry) {
        haptic(.generic)
        withAnimation(Self.settle) { onRemove(app) }
    }

    /// Ends whatever the pointer is doing. A lifted icon is dropped where it
    /// is, so its move is kept rather than thrown away.
    private func stopInteraction() {
        cancelScheduledLift()
        if lifted != nil { drop() }
        press = nil
        edgeTask?.cancel()
        edgeTask = nil
        edgeDirection = 0
    }

    private func endArranging() {
        stopInteraction()
        withAnimation(.easeOut(duration: 0.2)) { isArranging = false }
    }

    private func finishPageSwipe(_ value: DragGesture.Value, width: CGFloat) {
        let target = PageSwipe.target(from: currentPage, pageCount: totalPages, release: value, width: width)
        withAnimation(Self.pageTurn) {
            currentPage = target
            pageDragOffset = 0
        }
    }

    private func rubberBanded(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        PageSwipe.follow(translation, page: currentPage, pageCount: totalPages)
    }

    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: - Monitors

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape in a label field cancels the rename, not the arranging.
            guard event.keyCode == 53, editingAppId == nil else { return event }
            endArranging()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window else { return event }
            let locationInWindow = event.locationInWindow
            if let responder = window.firstResponder as? NSView {
                let frameInWindow = responder.convert(responder.bounds, to: nil)
                if frameInWindow.contains(locationInWindow) {
                    return event
                }
            }
            window.makeFirstResponder(nil)
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle())
                    .cursor(.pointingHand)
                    .onTapGesture {
                        withAnimation(Self.pageTurn) {
                            currentPage = index
                        }
                    }
            }
        }
    }
}

/// The arranging wiggle. Driven by a timeline rather than a repeating
/// animation: a `repeatForever` animation leaks into every other change made in
/// the same transaction, and would have set the icons' slide into slots
/// wobbling too. Paused, the timeline costs nothing, and keeping the same view
/// structure in both states lets the remove badges animate in.
private struct Wiggle: ViewModifier {
    let active: Bool
    let seed: String

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
            content
                .rotationEffect(.degrees(active ? angle(at: context.date) : 0))
                .animation(.easeOut(duration: 0.15), value: active)
        }
    }

    /// About two degrees each way, a little under four times a second, each icon
    /// out of step with its neighbours.
    private func angle(at date: Date) -> Double {
        let phase = Double(abs(seed.hashValue) % 628) / 100
        return sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 0.28 + phase) * 1.8
    }
}

struct DeleteBadge: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            // White glyph on a brand-red disc: hierarchical foregroundStyle takes
            // the mark first, the fill second.
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white, AppColors.brand)
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.borderless)
        .help("Remove from folder")
        .onHover { hovering in isHovered = hovering }
    }
}

struct RevertLabelButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .opacity(isHovered ? 0.4 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.borderless)
        .help("Use the app's own name")
        .onHover { hovering in isHovered = hovering }
    }
}
