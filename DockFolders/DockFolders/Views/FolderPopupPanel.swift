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

    func show(folder: DockFolder, mousePosition: NSPoint, onEdit: (() -> Void)? = nil) {
        // Toggle: if same folder was just dismissed (dock icon clicked again), don't reopen
        if let lastFolder = lastDismissedFolder,
           let lastTime = lastDismissTime,
           lastFolder == folder.name,
           Date().timeIntervalSince(lastTime) < 0.8 {
            lastDismissedFolder = nil
            return
        }

        closePanel()

        let cols = folder.gridConfig.columns
        let rows = Int(ceil(Double(folder.gridConfig.itemsPerPage) / Double(cols)))
        let cellW: CGFloat = 88
        let cellH: CGFloat = 90
        let gridSpacing: CGFloat = 2
        let hPad: CGFloat = 16
        let vPad: CGFloat = 16
        let hasPages = folder.apps.count > folder.gridConfig.itemsPerPage
        let arrowH: CGFloat = 5
        let pageDotsH: CGFloat = hasPages ? 19 : 0  // 4 top + 7 circle + 8 bottom

        let gridWidth = CGFloat(cols) * cellW + CGFloat(cols - 1) * gridSpacing
        let gridHeight = CGFloat(rows) * cellH + CGFloat(rows - 1) * gridSpacing
        let panelWidth = gridWidth + hPad * 2
        let panelHeight = gridHeight + vPad * 2 + pageDotsH + arrowH

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
        if let iconCenter = DockIconLocator.shared.iconCenter(forLauncherNamed: folder.name) {
            initialX = iconCenter.x
        } else {
            initialX = mousePosition.x
        }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePosition) })
            ?? NSScreen.main ?? NSScreen.screens[0]

        // Arrow always centered
        let arrowRelativeX = panelWidth / 2

        let popupView = FolderPopupView(
            folder: folder,
            onDismiss: { self.dismiss() },
            arrowX: arrowRelativeX,
            onEdit: {
                self.dismiss()
                onEdit?()
            }
        )
        panel.contentView = NSHostingView(rootView: popupView)

        // Position: arrow tip ~3px above the macOS APP_NAME tooltip position.
        // Default dock icons are ~48px, center ~24px from dock bottom.
        // APP_NAME tooltip appears ~2px above icon top edge.
        // Arrow tip target: iconCenter.y + 26 (half icon + 2px gap)
        let dockHeight: CGFloat = 60
        var origin = NSPoint(
            x: initialX - panelWidth / 2,
            y: screen.frame.origin.y + dockHeight
        )

        origin.x = max(screen.frame.origin.x + 4, min(origin.x, screen.frame.maxX - panelWidth - 4))
        origin.y = max(screen.frame.origin.y + 4, min(origin.y, screen.frame.maxY - panelHeight - 4))

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

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
            let useX = abs(scrollAccumX) > abs(scrollAccumY)
            let delta = useX ? scrollAccumX : scrollAccumY
            if abs(delta) > 8 {
                gestureTriggered = true
                if delta > 0 {
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
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
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
    var onEdit: (() -> Void)?

    @State private var currentPage = 0
    @State private var hoveredApp: String?
    @State private var slideDirection: Edge = .trailing

    private var pages: [[AppEntry]] {
        guard !folder.apps.isEmpty else { return [] }
        let perPage = folder.gridConfig.itemsPerPage
        return stride(from: 0, to: folder.apps.count, by: perPage).map { start in
            Array(folder.apps[start..<min(start + perPage, folder.apps.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    HStack(spacing: 7) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                                .frame(width: 7, height: 7)
                                .onTapGesture { goToPage(index) }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.vertical, 16)
        .background(
            ZStack {
                VisualEffectBackground()
                Color.black.opacity(0.1)
            }
            .clipShape(PopupShape(cornerRadius: 10, arrowX: arrowX))
        )
        .overlay(
            PopupShape(cornerRadius: 10, arrowX: arrowX)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
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

        return VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < apps.count {
                            appCell(apps[index])
                        } else {
                            Color.clear.frame(width: 88, height: 90)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func appCell(_ app: AppEntry) -> some View {
        let isHovered = hoveredApp == app.id

        return VStack(spacing: 4) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .scaleEffect(isHovered ? 1.15 : 1.0)

            Text(app.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.7))
                .frame(maxWidth: 76, alignment: .top)
                .frame(height: 26, alignment: .top)
        }
        .padding(6)
        .frame(width: 88, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.1 : 0))
        )
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
