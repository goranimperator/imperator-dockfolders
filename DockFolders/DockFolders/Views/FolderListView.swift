import SwiftUI

struct FolderListView: View {
    @EnvironmentObject var store: FolderStore
    @Binding var selectedFolder: DockFolder?
    @State private var folderToDelete: DockFolder?

    var body: some View {
        List(selection: $selectedFolder) {
            ForEach(store.folders) { folder in
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(folder.isInDock ? Color.accentColor : .secondary)
                    VStack(alignment: .leading) {
                        Text(folder.name)
                            .fontWeight(.medium)
                        Text("\(folder.apps.count) apps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if folder.isInDock {
                        Image(systemName: "dock.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
}
