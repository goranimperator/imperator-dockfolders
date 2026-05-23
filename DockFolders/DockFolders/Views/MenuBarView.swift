import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: FolderStore
    @State private var showNewFolderSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Imperator Dock Folders")
                    .font(.headline)
                Spacer()
                Button(action: { showNewFolderSheet = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.folders.isEmpty {
                Text("No folders yet")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.folders) { folder in
                            MenuBarFolderRow(folder: folder)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 400)
            }
        }
        .frame(width: 280)
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(isPresented: $showNewFolderSheet)
                .environmentObject(store)
        }
        .onAppear {
            store.reload()
        }
    }
}

struct MenuBarFolderRow: View {
    let folder: DockFolder
    @EnvironmentObject var store: FolderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(folder.isInDock ? Color.accentColor : .secondary)
                Text(folder.name)
                    .fontWeight(.medium)
                Spacer()
                Button(action: { store.toggleDock(for: folder) }) {
                    Image(systemName: folder.isInDock ? "minus.circle" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .help(folder.isInDock ? "Remove from Dock" : "Add to Dock")
            }

            if !folder.apps.isEmpty {
                HStack(spacing: 4) {
                    ForEach(folder.apps.prefix(6)) { app in
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    if folder.apps.count > 6 {
                        Text("+\(folder.apps.count - 6)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}
