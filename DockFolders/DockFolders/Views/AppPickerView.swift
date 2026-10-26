import SwiftUI
import UniformTypeIdentifiers

private struct PickerApp: Identifiable {
    let id: String
    let url: URL
    let name: String
    let icon: NSImage

    init(url: URL) {
        self.url = url
        self.id = url.absoluteString
        self.name = url.deletingPathExtension().lastPathComponent
        // BrandBook 22.2: resolve symlinks for Cryptex-mounted apps.
        let resolved = url.resolvingSymlinksInPath().path
        self.icon = NSWorkspace.shared.icon(forFile: resolved)
    }
}

struct AppPickerView: View {
    let folder: DockFolder
    @EnvironmentObject var store: FolderStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var allApps: [PickerApp] = []
    @State private var selectedURLs: Set<URL> = []
    @State private var isScanning = true

    private var filteredApps: [PickerApp] {
        if searchText.isEmpty { return allApps }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var existingAppPaths: Set<String> {
        Set(folder.apps.map { $0.url.path })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Add Apps")
                    .font(.headline)
                Spacer()
                Button("Done") { addSelectedAndClose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedURLs.isEmpty)
            }
            .padding()

            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search apps", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // The scan covers /Applications and, when it is switched on,
                // each external drive down to three levels. This reaches an app
                // anywhere else: deeper on a drive, on a network share, or on a
                // disk the user left out of the scan.
                Button("Choose Apps…") { chooseAppsFromDisk() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if isScanning {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for apps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No apps found" : "No apps match “\(searchText)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Choose Apps…") { chooseAppsFromDisk() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let apps = filteredApps
                        ForEach(0..<apps.count, id: \.self) { index in
                            appRow(apps[index])
                            if index < apps.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 420, height: 500)
        .task {
            // Walking every mounted drive can take a moment, and this used to
            // run on the main thread in onAppear, which froze the sheet while
            // it ran. The icons are read back on the main actor.
            let urls = await Task.detached(priority: .userInitiated) {
                AppDiscovery.installedApps()
            }.value
            allApps = urls.map { PickerApp(url: $0) }
            isScanning = false
        }
    }

    @ViewBuilder
    private func appRow(_ app: PickerApp) -> some View {
        let alreadyAdded = existingAppPaths.contains(app.url.path)
        let isSelected = selectedURLs.contains(app.url)
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 32, height: 32)
            Text(app.name)
            Spacer()
            if alreadyAdded {
                Text("Added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.brand)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .cursor(alreadyAdded ? .operationNotAllowed : .arrow)
        .onTapGesture {
            guard !alreadyAdded else { return }
            if isSelected {
                selectedURLs.remove(app.url)
            } else {
                selectedURLs.insert(app.url)
            }
        }
        .opacity(alreadyAdded ? 0.5 : 1.0)
    }

    private func chooseAppsFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = "Choose"
        panel.message = "Choose apps to add to this folder."
        guard panel.runModal() == .OK else { return }

        // Chosen apps join the list selected rather than being added straight
        // away, so every app in this sheet is added by the same Done button.
        for url in panel.urls where !existingAppPaths.contains(url.path) {
            if !allApps.contains(where: { $0.url == url }) {
                let app = PickerApp(url: url)
                let index = allApps.firstIndex {
                    $0.name.localizedCaseInsensitiveCompare(app.name) == .orderedDescending
                } ?? allApps.endIndex
                allApps.insert(app, at: index)
            }
            selectedURLs.insert(url)
        }
        // A search term that does not match the chosen app would hide the row
        // the user just picked.
        searchText = ""
    }

    private func addSelectedAndClose() {
        for url in selectedURLs {
            try? store.addApp(to: folder, appURL: url)
        }
        dismiss()
    }
}
