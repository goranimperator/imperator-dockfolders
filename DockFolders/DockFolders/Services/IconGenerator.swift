import AppKit

class IconGenerator {
    static func generateIconImage(for folderURL: URL) -> NSImage {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return NSImage() }

        let gridConfig = DockFoldersPath.loadGridConfig(in: folderURL)
        let columns = gridConfig.columns
        let itemsPerPage = gridConfig.itemsPerPage

        var appURLs = contents.filter { $0.pathExtension == "app" }

        let orderFile = folderURL.appendingPathComponent(".apporder")
        if let data = try? Data(contentsOf: orderFile),
           let order = try? JSONDecoder().decode([String].self, from: data) {
            appURLs.sort { a, b in
                let ai = order.firstIndex(of: a.lastPathComponent) ?? Int.max
                let bi = order.firstIndex(of: b.lastPathComponent) ?? Int.max
                return ai < bi
            }
        }

        let appIcons = appURLs.prefix(itemsPerPage).map { url -> NSImage in
            if let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) {
                return NSWorkspace.shared.icon(forFile: resolved.path)
            }
            return NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
        }

        let isDark = effectiveIsDark()
        return renderFolderIcon(appIcons: Array(appIcons), columns: columns, isDark: isDark)
    }

    static func generateIcon(for folderURL: URL) {
        let image = generateIconImage(for: folderURL)
        NSWorkspace.shared.setIcon(image, forFile: folderURL.path, options: [])

        let launcherURL = LauncherGenerator.launcherURL(for: folderURL)
        if FileManager.default.fileExists(atPath: launcherURL.path) {
            NSWorkspace.shared.setIcon(image, forFile: launcherURL.path, options: [])
        }
    }

    static func regenerateAllIcons() {
        let fm = FileManager.default
        let baseURL = DockFoldersPath.baseURL
        guard let contents = try? fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                generateIcon(for: url)
            }
        }
    }

    private static func effectiveIsDark() -> Bool {
        guard NSApp != nil else { return false }
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func renderFolderIcon(appIcons: [NSImage], columns: Int, isDark: Bool) -> NSImage {
        let size: CGFloat = 1024
        let inset: CGFloat = size * 0.10
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let bgSize = size - inset * 2
        let cornerRadius: CGFloat = bgSize * 180 / 1024
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

        if isDark {
            NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 0.7).setFill()
        } else {
            NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 0.6).setFill()
        }
        bgPath.fill()

        if isDark {
            NSColor(white: 1.0, alpha: 0.15).setStroke()
        } else {
            NSColor(white: 0.0, alpha: 0.12).setStroke()
        }
        bgPath.lineWidth = 4
        bgPath.stroke()

        if !appIcons.isEmpty {
            let rows = Int(ceil(Double(appIcons.count) / Double(columns)))
            let padding: CGFloat = bgSize * 0.12
            let spacing: CGFloat = bgSize * 0.04
            let available = bgSize - padding * 2 - spacing * CGFloat(max(columns, rows) - 1)
            let cellSize = available / CGFloat(max(columns, rows))

            let totalGridWidth = CGFloat(columns) * cellSize + CGFloat(columns - 1) * spacing
            let totalGridHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
            let offsetX = inset + (bgSize - totalGridWidth) / 2
            let offsetY = inset + (bgSize - totalGridHeight) / 2

            for (index, icon) in appIcons.enumerated() {
                let col = index % columns
                let row = rows - 1 - index / columns
                let x = offsetX + CGFloat(col) * (cellSize + spacing)
                let y = offsetY + CGFloat(row) * (cellSize + spacing)
                let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
                icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }

        image.unlockFocus()
        return image
    }
}
