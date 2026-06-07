import AppKit

/// Dark-mode check for icon generation. BrandBook 14.1 forces dark appearance
/// app-wide, so this effectively always returns true while the app is running.
/// Kept as a function so background icon-render tasks running before `NSApp`
/// is fully configured still resolve to a sensible value.
func effectiveIsDark() -> Bool {
    guard NSApp != nil else { return true }
    let appearance = NSApp.effectiveAppearance
    return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

@MainActor
class IconGenerator {
    nonisolated static func generateIconImage(for folderURL: URL) -> NSImage {
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

    nonisolated static func generateIcon(for folderURL: URL) {
        let image = generateIconImage(for: folderURL)
        NSWorkspace.shared.setIcon(image, forFile: folderURL.path, options: [])

        let launcherURL = LauncherGenerator.launcherURL(for: folderURL)
        if FileManager.default.fileExists(atPath: launcherURL.path) {
            // Regenerate entire launcher with proper .icns file
            LauncherGenerator.generateLauncher(for: folderURL)
        }
    }

    nonisolated static func regenerateAllIcons() {
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

    nonisolated private static func renderFolderIcon(appIcons: [NSImage], columns: Int, isDark: Bool) -> NSImage {
        let size: CGFloat = 1024
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Fill entire canvas — macOS applies its own squircle mask to .app icons
            if isDark {
                NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1.0).setFill()
            } else {
                NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1.0).setFill()
            }
            NSBezierPath(rect: rect).fill()

            if !appIcons.isEmpty {
                let rows = Int(ceil(Double(appIcons.count) / Double(columns)))
                let padding: CGFloat = size * 0.14
                let spacing: CGFloat = size * 0.04
                let available = size - padding * 2 - spacing * CGFloat(max(columns, rows) - 1)
                let cellSize = available / CGFloat(max(columns, rows))

                let totalGridWidth = CGFloat(columns) * cellSize + CGFloat(columns - 1) * spacing
                let totalGridHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
                let offsetX = (size - totalGridWidth) / 2
                let offsetY = (size - totalGridHeight) / 2

                for (index, icon) in appIcons.enumerated() {
                    let col = index % columns
                    let row = rows - 1 - index / columns
                    let x = offsetX + CGFloat(col) * (cellSize + spacing)
                    let y = offsetY + CGFloat(row) * (cellSize + spacing)
                    let iconRect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
                    icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }

            return true
        }
        return image
    }
}
