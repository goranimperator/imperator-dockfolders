import SwiftUI
import AppKit

struct PopupShape: Shape {
    let cornerRadius: CGFloat
    let arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        // Match macOS dock tooltip arrow style
        let arrowH: CGFloat = 5
        let arrowW: CGFloat = 12
        let r = cornerRadius
        let bodyH = rect.height - arrowH
        let tipX = min(max(arrowX, r + arrowW / 2 + 2), rect.width - r - arrowW / 2 - 2)

        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: rect.width - r, y: 0))
        p.addArc(tangent1End: CGPoint(x: rect.width, y: 0),
                 tangent2End: CGPoint(x: rect.width, y: r), radius: r)
        p.addLine(to: CGPoint(x: rect.width, y: bodyH - r))
        p.addArc(tangent1End: CGPoint(x: rect.width, y: bodyH),
                 tangent2End: CGPoint(x: rect.width - r, y: bodyH), radius: r)
        p.addLine(to: CGPoint(x: tipX + arrowW / 2, y: bodyH))
        p.addLine(to: CGPoint(x: tipX, y: rect.height))
        p.addLine(to: CGPoint(x: tipX - arrowW / 2, y: bodyH))
        p.addLine(to: CGPoint(x: r, y: bodyH))
        p.addArc(tangent1End: CGPoint(x: 0, y: bodyH),
                 tangent2End: CGPoint(x: 0, y: bodyH - r), radius: r)
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addArc(tangent1End: CGPoint(x: 0, y: 0),
                 tangent2End: CGPoint(x: r, y: 0), radius: r)
        p.closeSubpath()
        return p
    }
}

class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onScrollEvent: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScrollEvent?(event)
    }
}

@MainActor
class FolderPopupController {
    static let shared = FolderPopupController()

    private var panel: PopupPanel?
    private var cachedPanel: PopupPanel?
    private var mouseMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var dismissTimer: Timer?
    private var currentFolderName: String?
    private var lastDismissedFolder: String?
    private var lastDismissTime: Date?
    private var currentPanelWidth: CGFloat = 0

    func show(folder: DockFolder, mousePosition: NSPoint) {
        // Toggle: if same folder was just dismissed (dock icon clicked again), don't reopen
        if let lastFolder = lastDismissedFolder,
           let lastTime = lastDismissTime,
           lastFolder == folder.name,
           Date().timeIntervalSince(lastTime) < 0.8 {
            lastDismissedFolder = nil
            return
        }

        closePanel()

        let panel: PopupPanel
        if let cached = cachedPanel {
            panel = cached
            cachedPanel = nil
        } else {
            let p = PopupPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .popUpMenu
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.animationBehavior = .none
            p.acceptsMouseMovedEvents = true
            panel = p
        }

        // Use AX icon position for initial placement (same as tracking)
        let initialX: CGFloat
        let iconCenterY: CGFloat?
        if let iconCenter = DockIconLocator.shared.iconCenter(forLauncherNamed: folder.name) {
            initialX = iconCenter.x
            iconCenterY = iconCenter.y
        } else {
            initialX = mousePosition.x
            iconCenterY = nil
        }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePosition) })
            ?? NSScreen.main ?? NSScreen.screens[0]

        // Create view with temporary arrowX, measure, then set correct arrowX
        let popupView = FolderPopupView(
            folder: folder,
            onDismiss: { self.dismiss() },
            arrowX: 0
        )
        let hostingView = NSHostingView(rootView: popupView)
        let fittingSize = hostingView.fittingSize
        let panelWidth = ceil(fittingSize.width)
        let panelHeight = ceil(fittingSize.height)

        // Arrow always centered — update view with correct arrowX and locked height
        let arrowRelativeX = panelWidth / 2
        hostingView.rootView = FolderPopupView(
            folder: folder,
            onDismiss: { self.dismiss() },
            arrowX: arrowRelativeX,
            fixedHeight: panelHeight
        )
        panel.contentView = hostingView

        // Position: arrow tip just above the dock icon top edge.
        // AX iconCenter.y is the icon's vertical center. Icons are ~48px tall.
        // Arrow tip = iconCenter.y + 26 (half icon + 2px gap)
        let arrowTipY: CGFloat
        if let iconY = iconCenterY {
            arrowTipY = iconY + 25
        } else {
            arrowTipY = screen.frame.origin.y + 60
        }
        var origin = NSPoint(
            x: initialX - panelWidth / 2 + 1,
            y: arrowTipY
        )

        origin.x = max(screen.frame.origin.x + 4, min(origin.x, screen.frame.maxX - panelWidth - 4))
        origin.y = max(screen.frame.origin.y + 4, min(origin.y, screen.frame.maxY - panelHeight - 4))

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()

        var scrollAccumX: CGFloat = 0
        var scrollAccumY: CGFloat = 0
        var gestureTriggered = false
        panel.onScrollEvent = { event in
            if event.phase == .began {
                scrollAccumX = 0
                scrollAccumY = 0
                gestureTriggered = false
            }

            if event.phase == .cancelled || event.phase == .ended {
                scrollAccumX = 0
                scrollAccumY = 0
                gestureTriggered = false
                return
            }

            if event.momentumPhase != [] {
                return
            }

            guard !gestureTriggered else { return }

            scrollAccumX += event.scrollingDeltaX
            scrollAccumY += event.scrollingDeltaY

            // Only horizontal swipe triggers page change
            guard abs(scrollAccumX) > abs(scrollAccumY) else { return }
            if abs(scrollAccumX) > 8 {
                gestureTriggered = true
                if scrollAccumX > 0 {
                    NotificationCenter.default.post(name: .popupPrevPage, object: nil)
                } else {
                    NotificationCenter.default.post(name: .popupNextPage, object: nil)
                }
            }
        }

        currentFolderName = folder.name
        currentPanelWidth = panelWidth
        self.panel = panel

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }

        // Track mouse movement to follow dock icon position
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updatePanelPosition()
        }

        // Timer-based dismiss: check mouse position every 200ms (reliable even when Dock captures events)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMouseDismiss()
            }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }
            return event
        }
    }

    private func updatePanelPosition() {
        guard let panel = panel,
              let folderName = currentFolderName,
              let iconCenter = DockIconLocator.shared.iconCenter(forLauncherNamed: folderName)
        else { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        var newX = iconCenter.x - currentPanelWidth / 2
        newX = max(screen.frame.origin.x + 4, min(newX, screen.frame.maxX - currentPanelWidth - 4))

        var frame = panel.frame
        frame.origin.x = newX
        panel.setFrame(frame, display: false)
    }

    private func checkMouseDismiss() {
        guard let panel = panel else { return }
        let mouse = NSEvent.mouseLocation
        let panelFrame = panel.frame

        // Keep open if mouse is inside the popup panel (with small margin)
        let expandedPanel = panelFrame.insetBy(dx: -8, dy: -8)
        if expandedPanel.contains(mouse) { return }

        // Keep open if mouse is in the dock area (below the panel)
        if mouse.y < panelFrame.minY {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            if mouse.y >= screen.frame.origin.y { return }
        }

        // Mouse is above the panel or far to the sides — dismiss
        dismiss()
    }

    func dismiss() {
        guard let p = panel else { return }

        lastDismissedFolder = currentFolderName
        lastDismissTime = Date()

        p.orderOut(nil)

        cachedPanel = p
        panel = nil
        currentFolderName = nil
        removeMonitors()
    }

    private func closePanel() {
        if let p = panel {
            p.orderOut(nil)
            cachedPanel = p
        }
        panel = nil
        currentFolderName = nil
        removeMonitors()
    }

    private func removeMonitors() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = mouseMoveMonitor { NSEvent.removeMonitor(m); mouseMoveMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        dismissTimer?.invalidate(); dismissTimer = nil
    }
}

extension Notification.Name {
    static let popupNextPage = Notification.Name("dockfolders.nextPage")
    static let popupPrevPage = Notification.Name("dockfolders.prevPage")
}

struct FolderPopupView: View {
    let folder: DockFolder
    let onDismiss: () -> Void
    let arrowX: CGFloat
    var fixedHeight: CGFloat = 0

    @AppStorage("cutAppNames") private var cutAppNames: Bool = false
    @State private var currentPage = 0
    @State private var hoveredApp: String?
    @State private var slideDirection: Edge = .trailing

    private var labels: [String: String] {
        DockFoldersPath.loadLabels(in: folder.url)
    }

    private var pages: [[AppEntry]] {
        guard !folder.apps.isEmpty else { return [] }
        let perPage = folder.gridConfig.itemsPerPage
        return stride(from: 0, to: folder.apps.count, by: perPage).map { start in
            Array(folder.apps[start..<min(start + perPage, folder.apps.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(folder.name)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 10)

            if pages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No apps")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                gridPage(pages[currentPage])
                    .id(currentPage)
                    .transition(.asymmetric(
                        insertion: .move(edge: slideDirection),
                        removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
                    ))

                if pages.count > 1 {
                    Spacer().frame(height: 20)
                }
            }
        }
        .padding(16)
        .frame(height: fixedHeight > 0 ? fixedHeight : nil, alignment: .top)
        .overlay(alignment: .bottom) {
            if pages.count > 1 {
                HStack(spacing: 9) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                            .frame(width: 7, height: 7)
                            .onTapGesture { goToPage(index) }
                    }
                }
                .padding(.bottom, 18)
            }
        }
        .background(
            VisualEffectBackground()
                .clipShape(PopupShape(cornerRadius: 28, arrowX: arrowX))
        )
        .clipped()
        .onReceive(NotificationCenter.default.publisher(for: .popupNextPage)) { _ in
            if currentPage < pages.count - 1 { goToPage(currentPage + 1) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popupPrevPage)) { _ in
            if currentPage > 0 { goToPage(currentPage - 1) }
        }
    }

    private func goToPage(_ index: Int) {
        slideDirection = index > currentPage ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage = index
        }
    }

    private func gridPage(_ apps: [AppEntry]) -> some View {
        let cols = folder.gridConfig.columns
        let rows = Int(ceil(Double(folder.gridConfig.itemsPerPage) / Double(cols)))

        return VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 6) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < apps.count {
                            appCell(apps[index])
                        } else {
                            Color.clear.frame(width: cutAppNames ? 60 : 88).frame(maxHeight: .infinity)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appCell(_ app: AppEntry) -> some View {
        let isHovered = hoveredApp == app.id
        let customLabel = labels[app.localURL.lastPathComponent]
        let displayName = customLabel ?? app.name
        // Cell width is always uniform. Only the line count changes:
        // cut mode + auto name → 1 line truncated; otherwise 2 lines.
        let textLines = (cutAppNames && customLabel == nil) ? 1 : 2

        return VStack(spacing: 2) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .scaleEffect(isHovered ? 1.15 : 1.0)

            Text(displayName)
                .font(.system(size: 10))
                .lineLimit(textLines)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.7))
                .frame(maxWidth: 76)
        }
        .padding(.vertical, 6)
        .frame(width: 88)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            hoveredApp = hovering ? app.id : nil
        }
        .onTapGesture {
            NSWorkspace.shared.open(app.url)
            onDismiss()
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
