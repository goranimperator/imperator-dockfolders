import Foundation
import AppKit

enum DockFoldersPath {
    static let baseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DockFolders")
    }()

    static func loadGridConfig(in folderURL: URL) -> GridConfig {
        let file = folderURL.appendingPathComponent(".gridconfig")
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(GridConfig.self, from: data) else {
            return .default
        }
        return config
    }
}

@MainActor
class FolderStore: ObservableObject {
    static var baseURL: URL { DockFoldersPath.baseURL }

    @Published var folders: [DockFolder] = []

    private let fm = FileManager.default

    init() {
        ensureBaseDirectory()
        migrateAliasesToSymlinks()
        reload()
    }

    private func ensureBaseDirectory() {
        if !fm.fileExists(atPath: Self.baseURL.path) {
            try? fm.createDirectory(at: Self.baseURL, withIntermediateDirectories: true)
        }
    }

    private func migrateAliasesToSymlinks() {
        guard let folders = try? fm.contentsOfDirectory(
            at: Self.baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for folderURL in folders {
            guard (try? folderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let items = try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isAliasFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in items where item.pathExtension == "app" {
                let vals = try? item.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
                let isAlias = vals?.isAliasFile == true
                let isSymlink = vals?.isSymbolicLink == true

                if isAlias && !isSymlink {
                    guard let resolved = try? URL(resolvingAliasFileAt: item, options: [.withoutUI, .withoutMounting]) else { continue }
                    try? fm.removeItem(at: item)
                    try? fm.createSymbolicLink(at: item, withDestinationURL: resolved)
                }
            }
        }
    }

    /// Load a single folder by name without reloading the entire store.
    /// Used by the popup path for faster display.
    func loadFolder(named name: String) -> DockFolder? {
        let folderURL = Self.baseURL.appendingPathComponent(name)
        guard fm.fileExists(atPath: folderURL.path) else { return nil }
        let apps = loadApps(in: folderURL)
        let isInDock = DockController.shared.isFolderInDock(folderURL)
        let gridConfig = Self.loadGridConfig(in: folderURL)
        return DockFolder(id: folderURL.path, name: name, apps: apps, isInDock: isInDock, gridConfig: gridConfig)
    }

    func reload() {
        guard let contents = try? fm.contentsOfDirectory(
            at: Self.baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            folders = []
            return
        }

        let allFolders = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { folderURL in
                let name = folderURL.lastPathComponent
                let apps = loadApps(in: folderURL)
                let isInDock = DockController.shared.isFolderInDock(folderURL)
                let gridConfig = Self.loadGridConfig(in: folderURL)
                return DockFolder(id: folderURL.path, name: name, apps: apps, isInDock: isInDock, gridConfig: gridConfig)
            }

        let savedOrder = loadFolderOrder()
        if savedOrder.isEmpty {
            folders = allFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            var ordered: [DockFolder] = []
            var remaining = allFolders
            for name in savedOrder {
                if let idx = remaining.firstIndex(where: { $0.name == name }) {
                    ordered.append(remaining.remove(at: idx))
                }
            }
            ordered.append(contentsOf: remaining.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            folders = ordered
        }
    }

    private func loadApps(in folderURL: URL) -> [AppEntry] {
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isAliasFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let apps = contents
            .filter { $0.pathExtension == "app" }
            .compactMap { localURL -> AppEntry? in
                guard let resolved = try? URL(resolvingAliasFileAt: localURL, options: [.withoutUI, .withoutMounting]) else {
                    return nil
                }
                return AppEntry(localURL: localURL, resolvedURL: resolved)
            }

        let order = loadOrder(in: folderURL)
        if order.isEmpty {
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        var ordered: [AppEntry] = []
        for name in order {
            if let app = apps.first(where: { $0.localURL.lastPathComponent == name }) {
                ordered.append(app)
            }
        }
        for app in apps where !ordered.contains(where: { $0.id == app.id }) {
            ordered.append(app)
        }
        return ordered
    }

    private func loadOrder(in folderURL: URL) -> [String] {
        let orderFile = folderURL.appendingPathComponent(".apporder")
        guard let data = try? Data(contentsOf: orderFile),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }

    private func saveOrder(_ apps: [AppEntry], in folderURL: URL) {
        let orderFile = folderURL.appendingPathComponent(".apporder")
        let names = apps.map { $0.localURL.lastPathComponent }
        if let data = try? JSONEncoder().encode(names) {
            try? data.write(to: orderFile)
        }
    }

    static func loadGridConfig(in folderURL: URL) -> GridConfig {
        DockFoldersPath.loadGridConfig(in: folderURL)
    }

    func saveGridConfig(for folder: DockFolder, config: GridConfig) {
        let file = folder.url.appendingPathComponent(".gridconfig")
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: file)
        }

        if folder.isInDock {
            IconGenerator.generateIcon(for: folder.url)
            DockController.shared.refreshDock()
        }

        reload()
    }

    func reorderFolders(to newOrder: [DockFolder]) {
        folders = newOrder
        saveFolderOrder()
    }

    private func loadFolderOrder() -> [String] {
        let file = Self.baseURL.appendingPathComponent(".folderorder")
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }

    private func saveFolderOrder() {
        let file = Self.baseURL.appendingPathComponent(".folderorder")
        let names = folders.map { $0.name }
        if let data = try? JSONEncoder().encode(names) {
            try? data.write(to: file)
        }
    }

    func reorderApps(in folder: DockFolder, to newOrder: [AppEntry]) {
        saveOrder(newOrder, in: folder.url)

        if folder.isInDock {
            IconGenerator.generateIcon(for: folder.url)
            DockController.shared.refreshDock()
        }

        reload()
    }

    func createFolder(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = Self.baseURL.appendingPathComponent(trimmed)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        reload()
    }

    func deleteFolder(_ folder: DockFolder) throws {
        if folder.isInDock {
            DockController.shared.removeFromDock(folder.url)
        }
        try fm.removeItem(at: folder.url)
        reload()
    }

    func renameFolder(_ folder: DockFolder, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }

        let wasInDock = folder.isInDock
        if wasInDock {
            DockController.shared.removeFromDock(folder.url)
        }

        let newURL = Self.baseURL.appendingPathComponent(trimmed)
        try fm.moveItem(at: folder.url, to: newURL)

        if wasInDock {
            IconGenerator.generateIcon(for: newURL)
            DockController.shared.addToDock(newURL)
        }

        reload()
    }

    func addApp(to folder: DockFolder, appURL: URL) throws {
        let linkName = appURL.lastPathComponent
        let linkURL = folder.url.appendingPathComponent(linkName)

        guard !fm.fileExists(atPath: linkURL.path) else { return }

        try fm.createSymbolicLink(at: linkURL, withDestinationURL: appURL)

        if folder.isInDock {
            IconGenerator.generateIcon(for: folder.url)
            DockController.shared.refreshDock()
        }

        reload()
    }

    func removeApp(from folder: DockFolder, app: AppEntry) throws {
        try? fm.removeItem(at: app.localURL)

        if folder.isInDock {
            IconGenerator.generateIcon(for: folder.url)
            DockController.shared.refreshDock()
        }

        reload()
    }

    func toggleDock(for folder: DockFolder) {
        if folder.isInDock {
            DockController.shared.removeFromDock(folder.url)
        } else {
            IconGenerator.generateIcon(for: folder.url)
            DockController.shared.addToDock(folder.url)
        }
        reload()
    }
}
