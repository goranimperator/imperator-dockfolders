import SwiftUI

struct FolderListView: View {
    @EnvironmentObject var store: FolderStore
    @Binding var selectedFolder: DockFolder?
    @State private var folderToDelete: DockFolder?
    @State private var editingFolder: DockFolder?
    @State private var editedName: String = ""
    @State private var hoveredFolder: String?

    var body: some View {
        List(selection: $selectedFolder) {
            ForEach(store.folders) { folder in
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(folder.isInDock ? Color.accentColor : .secondary)
                    if editingFolder == folder {
                        TextField("Folder name", text: $editedName, onCommit: {
                            commitRename(folder)
                        })
                        .textFieldStyle(.roundedBorder)
                    } else {
                        VStack(alignment: .leading) {
                            Text(folder.name)
                                .fontWeight(.medium)
                            Text("\(folder.apps.count) apps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if hoveredFolder == folder.id && editingFolder != folder {
                        Button(action: {
                            editedName = folder.name
                            editingFolder = folder
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Rename")

                        Button(action: { folderToDelete = folder }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete")
                    } else if folder.isInDock && editingFolder != folder {
                        Image(systemName: "dock.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onHover { hovering in
                    hoveredFolder = hovering ? folder.id : nil
                }
                .tag(folder)
                .contextMenu {
                    Button(folder.isInDock ? "Remove from Dock" : "Add to Dock") {
                        store.toggleDock(for: folder)
                    }
                    Divider()
                    Button("Delete Folder", role: .destructive) {
                        folderToDelete = folder
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .onTapGesture {
            // Commit any in-progress rename when clicking elsewhere
            if let folder = editingFolder {
                commitRename(folder)
            }
        }
        .alert("Delete folder?", isPresented: Binding(
            get: { folderToDelete != nil },
            set: { if !$0 { folderToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { folderToDelete = nil }
            Button("Delete", role: .destructive) {
                if let folder = folderToDelete {
                    try? store.deleteFolder(folder)
                    if selectedFolder == folder {
                        selectedFolder = nil
                    }
                    folderToDelete = nil
                }
            }
        } message: {
            if let folder = folderToDelete {
                Text("The folder \"\(folder.name)\" and all shortcuts in it will be deleted. The original apps are not affected.")
            }
        }
    }

    private func commitRename(_ folder: DockFolder) {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        editingFolder = nil
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        do {
            try store.renameFolder(folder, to: trimmed)
            if selectedFolder?.name == folder.name {
                selectedFolder = store.folders.first { $0.name == trimmed }
            }
        } catch {
            // Rename failed — name reverts visually on next reload
        }
    }
}
