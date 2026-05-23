import Foundation

struct GridConfig: Codable, Hashable {
    var columns: Int
    var itemsPerPage: Int

    static let `default` = GridConfig(columns: 3, itemsPerPage: 9)
}

struct DockFolder: Identifiable, Hashable {
    let id: String
    var name: String
    var apps: [AppEntry]
    var isInDock: Bool
    var gridConfig: GridConfig

    var url: URL {
        DockFoldersPath.baseURL.appendingPathComponent(name)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DockFolder, rhs: DockFolder) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.isInDock == rhs.isInDock
            && lhs.apps == rhs.apps
            && lhs.gridConfig == rhs.gridConfig
    }
}
