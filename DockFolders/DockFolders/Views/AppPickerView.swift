import SwiftUI

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

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

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
        .frame(width: 420, height: 500)
        .onAppear {
            allApps = AppDiscovery.installedApps().map { PickerApp(url: $0) }
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

    private func addSelectedAndClose() {
        for url in selectedURLs {
            try? store.addApp(to: folder, appURL: url)
        }
        dismiss()
    }
}
