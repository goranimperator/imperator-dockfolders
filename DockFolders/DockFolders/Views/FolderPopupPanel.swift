import SwiftUI
import AppKit

struct PopupShape: Shape {
    let cornerRadius: CGFloat
    let arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let arrowH: CGFloat = 12
        let arrowW: CGFloat = 22
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
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?

    func show(folder: DockFolder, mousePosition: NSPoint, onEdit: (() -> Void)? = nil) {
        dismiss()

        let cols = folder.gridConfig.columns
        let rows = Int(ceil(Double(folder.gridConfig.itemsPerPage) / Double(cols)))
        let cellW: CGFloat = 88
        let cellH: CGFloat = 90
        let gridSpacing: CGFloat = 2
        let hPad: CGFloat = 16
        let hasPages = folder.apps.count > folder.gridConfig.itemsPerPage
        let arrowH: CGFloat = 12

        let gridWidth = CGFloat(cols) * cellW + CGFloat(cols - 1) * gridSpacing
        let gridHeight = CGFloat(rows) * cellH + CGFloat(rows - 1) * gridSpacing
        let panelWidth = gridWidth + hPad * 2
        let panelHeight = gridHeight + 40 + (hasPages ? 28 : 12) + arrowH

        let panel = PopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.acceptsMouseMovedEvents = true

        let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePosition) })
            ?? NSScreen.main ?? NSScreen.screens[0]

        let dockHeight: CGFloat = 75
        var origin = NSPoint(
            x: mousePosition.x - panelWidth / 2,
            y: screen.frame.origin.y + dockHeight
        )

        origin.x = max(screen.frame.origin.x + 4, min(origin.x, screen.frame.maxX - panelWidth - 4))
        origin.y = max(screen.frame.origin.y + 4, min(origin.y, screen.frame.maxY - panelHeight - 4))

        let arrowRelativeX = mousePosition.x - origin.x

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

        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.06
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

        self.panel = panel

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }
            return event
        }
    }

    func dismiss() {
        if let p = panel {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.08
                p.animator().alphaValue = 0
            }, completionHandler: { p.close() })
        }
        panel = nil
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
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
            Text(folder.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 14)
                .padding(.bottom, 8)

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
                    .padding(.bottom, 10)
                } else {
                    Spacer().frame(height: 10)
                }
            }

            Spacer().frame(height: 12)
        }
        .background(
            ZStack {
                VisualEffectBackground()
                Color.black.opacity(0.1)
            }
            .clipShape(PopupShape(cornerRadius: 14, arrowX: arrowX))
        )
        .overlay(
            PopupShape(cornerRadius: 14, arrowX: arrowX)
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

        return VStack(spacing: 2) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .scaleEffect(isHovered ? 1.15 : 1.0)

            Text(app.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.7))
                .frame(maxWidth: 80)
                .frame(height: 28)
        }
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
