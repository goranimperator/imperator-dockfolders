import SwiftUI
import UniformTypeIdentifiers

struct FolderDetailView: View {
    let folder: DockFolder
    @EnvironmentObject var store: FolderStore
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var showAppPicker = false
    @State private var showGridSettings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            Divider()

            if showGridSettings {
                GridSettingsBar(folder: folder)
                Divider()
            }

            if folder.apps.isEmpty {
                emptyState
            } else {
                AppGridCarousel(
                    apps: folder.apps,
                    columns: folder.gridConfig.columns,
                    itemsPerPage: folder.gridConfig.itemsPerPage,
                    onRemove: removeApp,
                    onReorder: { newOrder in
                        store.reorderApps(in: folder, to: newOrder)
                    }
                )
            }
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(folder: folder)
        }
    }

    private var header: some View {
        HStack {
            if isEditing {
                TextField("Folder name", text: $editedName, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
                Button("Done") { commitRename() }
            } else {
                Text(folder.name)
                    .font(.title2)
                    .fontWeight(.bold)
                Button(action: {
                    editedName = folder.name
                    isEditing = true
                }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button(action: { withAnimation { showGridSettings.toggle() } }) {
                Image(systemName: "square.grid.3x3")
                    .foregroundStyle(showGridSettings ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Grid settings")

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
                .foregroundStyle(.secondary)
            Text("No apps yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Add Apps") { showAppPicker = true }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != folder.name {
            try? store.renameFolder(folder, to: trimmed)
        }
        isEditing = false
    }

    private func removeApp(_ app: AppEntry) {
        try? store.removeApp(from: folder, app: app)
    }
}

struct GridSettingsBar: View {
    let folder: DockFolder
    @EnvironmentObject var store: FolderStore

    private let columnOptions = [2, 3, 4, 5]
    private let pageOptions = [4, 6, 8, 9, 12, 15, 16, 20, 25]

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

            Button(action: {
                IconGenerator.generateIcon(for: folder.url)
                if folder.isInDock {
                    DockController.shared.refreshDock()
                }
            }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Update dock icon")

            gridPreview
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
                            .fill(index < folder.gridConfig.itemsPerPage ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15))
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

class ScrollWheelNSView: NSView {
    var onScrollEvent: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScrollEvent?(event)
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

struct AppGridCarousel: View {
    let apps: [AppEntry]
    let columns: Int
    let itemsPerPage: Int
    let onRemove: (AppEntry) -> Void
    let onReorder: ([AppEntry]) -> Void

    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var draggingApp: AppEntry?
    @State private var dropTargetApp: AppEntry?
    @State private var edgeHoverLeft = false
    @State private var edgeHoverRight = false
    @State private var edgeTimer: Timer?
    @State private var scrollAccumX: CGFloat = 0
    @State private var scrollAccumY: CGFloat = 0
    @State private var scrollGestureTriggered = false

    private var pages: [[AppEntry]] {
        stride(from: 0, to: apps.count, by: itemsPerPage).map { start in
            Array(apps[start..<min(start + itemsPerPage, apps.count)])
        }
    }

    private var totalPages: Int { pages.count }
    private var isDragging: Bool { draggingApp != nil }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    HStack(spacing: 0) {
                        ForEach(0..<totalPages, id: \.self) { pageIndex in
                            gridPage(pages[pageIndex], containerWidth: geo.size.width, containerHeight: geo.size.height)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * geo.size.width + dragOffset)
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: currentPage)
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    dragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                if !isDragging {
                                    let threshold = geo.size.width * 0.2
                                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                                        if value.translation.width < -threshold && currentPage < totalPages - 1 {
                                            currentPage += 1
                                        } else if value.translation.width > threshold && currentPage > 0 {
                                            currentPage -= 1
                                        }
                                        dragOffset = 0
                                    }
                                }
                            }
                    )

                    if isDragging && totalPages > 1 {
                        HStack(spacing: 0) {
                            edgeDropZone(direction: .left)
                                .frame(width: 50, height: geo.size.height)
                            Spacer()
                            edgeDropZone(direction: .right)
                                .frame(width: 50, height: geo.size.height)
                        }
                    }
                }
                .background(
                    ScrollWheelOverlay { event in
                        if event.phase == .began {
                            scrollAccumX = 0
                            scrollAccumY = 0
                            scrollGestureTriggered = false
                        }
                        if event.phase == .cancelled || event.phase == .ended {
                            scrollAccumX = 0
                            scrollAccumY = 0
                            scrollGestureTriggered = false
                            return
                        }
                        if event.momentumPhase != [] { return }
                        guard !scrollGestureTriggered else { return }
                        scrollAccumX += event.scrollingDeltaX
                        scrollAccumY += event.scrollingDeltaY
                        let useX = abs(scrollAccumX) > abs(scrollAccumY)
                        let delta = useX ? scrollAccumX : scrollAccumY
                        if abs(delta) > 10 {
                            scrollGestureTriggered = true
                            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                                if (useX ? delta > 0 : delta < 0) && currentPage > 0 {
                                    currentPage -= 1
                                } else if (useX ? delta < 0 : delta > 0) && currentPage < totalPages - 1 {
                                    currentPage += 1
                                }
                            }
                        }
                    }
                )
            }

            if totalPages > 1 {
                pageIndicator
                    .padding(.vertical, 12)
            }
        }
        .onChange(of: apps.count) { _, _ in
            let maxPage = max(0, totalPages - 1)
            if currentPage > maxPage {
                currentPage = maxPage
            }
        }
    }

    private enum EdgeDirection {
        case left, right
    }

    private func edgeDropZone(direction: EdgeDirection) -> some View {
        let isActive = direction == .left ? edgeHoverLeft : edgeHoverRight
        let canNavigate = direction == .left ? currentPage > 0 : currentPage < totalPages - 1

        return Rectangle()
            .fill(canNavigate && isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(alignment: direction == .left ? .leading : .trailing) {
                if canNavigate {
                    Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .opacity(isActive ? 1 : 0.5)
                }
            }
            .onDrop(of: [UTType.text], isTargeted: Binding(
                get: { direction == .left ? edgeHoverLeft : edgeHoverRight },
                set: { hovering in
                    if direction == .left {
                        edgeHoverLeft = hovering
                    } else {
                        edgeHoverRight = hovering
                    }
                    if hovering && canNavigate {
                        startEdgeTimer(direction: direction)
                    } else {
                        cancelEdgeTimer()
                    }
                }
            )) { _ in
                false
            }
    }

    private func startEdgeTimer(direction: EdgeDirection) {
        cancelEdgeTimer()
        edgeTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                    if direction == .left && currentPage > 0 {
                        currentPage -= 1
                    } else if direction == .right && currentPage < totalPages - 1 {
                        currentPage += 1
                    }
                }
            }
        }
    }

    private func cancelEdgeTimer() {
        edgeTimer?.invalidate()
        edgeTimer = nil
    }

    private func gridPage(_ pageApps: [AppEntry], containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        let rows = Int(ceil(Double(itemsPerPage) / Double(columns)))
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 24
        let availableWidth = containerWidth - horizontalPadding * 2 - spacing * CGFloat(columns - 1)
        let availableHeight = containerHeight - 24 - spacing * CGFloat(rows - 1)
        let cellWidth = availableWidth / CGFloat(columns)
        let cellHeight = min(availableHeight / CGFloat(rows), cellWidth * 1.2)

        return VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = row * columns + col
                        if index < pageApps.count {
                            appCell(pageApps[index], width: cellWidth, height: cellHeight)
                        } else {
                            emptyCell(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 12)
    }

    private func emptyCell(width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                guard let source = draggingApp else { return false }
                var reordered = apps
                guard let fromIndex = reordered.firstIndex(where: { $0.id == source.id }) else {
                    draggingApp = nil
                    return false
                }
                reordered.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: reordered.endIndex)
                draggingApp = nil
                dropTargetApp = nil
                onReorder(reordered)
                return true
            }
    }

    private func appCell(_ app: AppEntry, width: CGFloat, height: CGFloat) -> some View {
        let iconSize = min(width * 0.55, height * 0.55)
        let isDropTarget = dropTargetApp == app && draggingApp != app
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)

                Button(action: { onRemove(app) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.borderless)
                .offset(x: 4, y: -4)
            }

            Text(app.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: width - 4)

            if !app.exists {
                Text("Missing")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(width: width, height: height)
        .opacity(draggingApp == app ? 0.4 : 1.0)
        .scaleEffect(isDropTarget ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDropTarget)
        .onDrag {
            draggingApp = app
            return NSItemProvider(object: app.id as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: Binding(
            get: { dropTargetApp == app },
            set: { if $0 { dropTargetApp = app } else if dropTargetApp == app { dropTargetApp = nil } }
        )) { _ in
            guard let source = draggingApp, source != app else {
                draggingApp = nil
                dropTargetApp = nil
                return false
            }

            var reordered = apps
            guard let fromIndex = reordered.firstIndex(where: { $0.id == source.id }),
                  let toIndex = reordered.firstIndex(where: { $0.id == app.id }) else {
                draggingApp = nil
                dropTargetApp = nil
                return false
            }

            reordered.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            draggingApp = nil
            dropTargetApp = nil
            onReorder(reordered)
            return true
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .onTapGesture {
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                            currentPage = index
                        }
                    }
            }
        }
    }
}
