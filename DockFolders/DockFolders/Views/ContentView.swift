import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: FolderStore
    @State private var selectedFolder: DockFolder?
    @State private var showNewFolderSheet = false
    @State private var showSidebar = true

    var body: some View {
        HSplitView {
            if showSidebar {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        SigilView(size: 13)
                        Text("Imperator Dock Folders")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    Divider()

                    FolderListView(selectedFolder: $selectedFolder)
                }
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)
            }

            if let folder = selectedFolder {
                FolderDetailView(folder: folder, selectedFolder: $selectedFolder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a folder")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showNewFolderSheet = true }) {
                    Label("New Folder", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { withAnimation { showSidebar.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(isPresented: $showNewFolderSheet)
        }
        .onChange(of: store.folders) { _, newFolders in
            if let sel = selectedFolder {
                selectedFolder = newFolders.first { $0.name == sel.name }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.reload()
        }
    }
}

struct NewFolderSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var store: FolderStore
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("New Folder")
                .font(.headline)

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { create() }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }

    private func create() {
        do {
            try store.createFolder(name: name)
            isPresented = false
        } catch {
            errorMessage = "Could not create folder: \(error.localizedDescription)"
        }
    }
}
