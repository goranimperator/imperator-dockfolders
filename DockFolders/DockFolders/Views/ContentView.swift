import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: FolderStore
    @State private var selectedFolder: DockFolder?
    @State private var showNewFolderSheet = false
    @State private var showSidebar = true
    @State private var addFolderHovered = false
    @State private var refreshHovered = false
    @State private var refreshSpinAngle: Double = 0
    @AppStorage("cutAppNames") private var cutAppNames: Bool = false

    var body: some View {
        HSplitView {
            if showSidebar {
                VStack(spacing: 0) {
                    HStack {
                        Text("Imperator Dock Folders")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(action: {
                            withAnimation(.interpolatingSpring(stiffness: 40, damping: 5)) {
                                refreshSpinAngle += 360
                            }
                            store.refreshAll()
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(refreshSpinAngle))
                                .opacity(refreshHovered ? 1.0 : 0.4)
                        }
                        .buttonStyle(.borderless)
                        .onHover { h in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                refreshHovered = h
                            }
                        }
                        .help("Refresh all folders")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    Divider()

                    HStack {
                        Text("Cut app names")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $cutAppNames)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)

                    Divider()

                    FolderListView(selectedFolder: $selectedFolder)

                    Divider()

                    HStack {
                        Button(action: { showNewFolderSheet = true }) {
                            Label("Add Folder", systemImage: "plus.circle.fill")
                                .font(.system(size: 13))
                                .opacity(addFolderHovered ? 1.0 : 0.5)
                        }
                        .buttonStyle(.borderless)
                        .onHover { h in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                addFolderHovered = h
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
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
                Button(action: { withAnimation { showSidebar.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(isPresented: $showNewFolderSheet, selectedFolder: $selectedFolder)
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
    var selectedFolder: Binding<DockFolder?>?
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.createFolder(name: trimmed)
            selectedFolder?.wrappedValue = store.folders.first { $0.name == trimmed }
            isPresented = false
        } catch {
            errorMessage = "Could not create folder: \(error.localizedDescription)"
        }
    }
}
