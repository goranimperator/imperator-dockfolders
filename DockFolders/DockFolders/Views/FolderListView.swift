import SwiftUI

struct FolderListView: View {
    @EnvironmentObject var store: FolderStore
    @Binding var selectedFolder: DockFolder?
    @State private var folderToDelete: DockFolder?
    @State private var editingFolder: DockFolder?
    @State private var editedName: String = ""
    @State private var hoveredFolder: String?
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        List(selection: $selectedFolder) {
            ForEach(store.folders) { folder in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0xa0/255, green: 0x18/255, blue: 0x18/255))
                    if editingFolder == folder {
                        TextField("Folder name", text: $editedName, onCommit: {
                            commitRename(folder)
                        })
                        .textFieldStyle(.roundedBorder)
                        .focused($isRenameFieldFocused)
                    } else {
                        VStack(alignment: .leading) {
                            Text(folder.name)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text("\(folder.apps.count) apps")
                                .fontWeight(.medium)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            editedName = folder.name
                            editingFolder = folder
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isRenameFieldFocused = true
                            }
                        })
                    }
                    Spacer()
                    if editingFolder != folder {
                        let isHovered = hoveredFolder == folder.id
                        HStack(spacing: isHovered ? 6 : 0) {
                            if folder.isInDock {
                                Image(systemName: "dock.rectangle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }

                            Button(action: { folderToDelete = folder }) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete")
                            .frame(width: isHovered ? nil : 0)
                            .opacity(isHovered ? 1 : 0)
                            .clipped()
                        }
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
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
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }
            .onMove { from, to in
                var reordered = store.folders
                reordered.move(fromOffsets: from, toOffset: to)
                store.reorderFolders(to: reordered)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .onChange(of: isRenameFieldFocused) { _, focused in
            if !focused, let folder = editingFolder {
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
