import SwiftUI

struct ContentView: View {
    @Environment(FolderStore.self) private var store
    @State private var selectedFolder: DockFolder?
    @State private var showNewFolderSheet = false
    @State private var addFolderHovered = false
    @State private var refreshSpinAngle: Double = 0
    @State private var showResetNamesAlert = false
    @AppStorage("cutAppNames") private var cutAppNames: Bool = false
    @AppStorage("sidebarOptionsExpanded") private var optionsExpanded = false

    /// Width of the trailing control column in the sidebar settings rows. The
    /// switch, the refresh pill and the reset pill all sit in this column and
    /// are right-aligned inside it, so their right edges line up regardless of
    /// each control's own intrinsic width.
    private static let trailingControlWidth: CGFloat = 30

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
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

                    Divider()

                    optionsSection

                    Divider()

                    HStack {
                        LaunchAtLoginToggle()
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)

            if let folder = selectedFolder {
                FolderDetailView(folder: folder, selectedFolder: $selectedFolder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a folder")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(isPresented: $showNewFolderSheet, selectedFolder: $selectedFolder)
        }
        .alert("Reset all custom app names?", isPresented: $showResetNamesAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                store.resetAllLabelsAcrossFolders()
            }
        } message: {
            Text("All custom labels will be removed and every app will revert to its original name in every folder. This action cannot be undone.")
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

    /// The three folder-wide actions, folded away under Add Folder so the
    /// sidebar opens on the folders themselves. Button-based disclosure per
    /// BrandBook 7.4, not DisclosureGroup. Remembers whether it was open.
    ///
    /// Two departures from 7.4, both on Goran's call: the chevron sits at the
    /// trailing edge, in line with the row controls, so the title starts at the
    /// same x as the row labels instead of after the chevron. And the title
    /// sits a little closer to its rows than to the divider above, so it reads
    /// as their heading.
    private var optionsSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { optionsExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Folder options".uppercased())
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .accessibilityValue(optionsExpanded ? "Expanded" : "Collapsed")
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, optionsExpanded ? 9 : 10)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    optionRow(
                        "Cut app names",
                        detail: "Long names take one line in the Dock popup. Names you typed yourself always show in full."
                    ) {
                        Toggle("", isOn: $cutAppNames)
                            .toggleStyle(.switch)
                            .scaleEffect(0.55)
                            .tint(AppColors.brand)
                            .labelsHidden()
                            // scaleEffect only scales the rendering: the switch
                            // still claims its full 54x24 fitting size in layout,
                            // so without this the drawn capsule sits ~12pt short
                            // of the pills below it. Sizing the frame to the drawn
                            // size makes layout match what is on screen.
                            .frame(width: 54 * 0.55, height: 24 * 0.55)
                    }

                    optionRow(
                        "Refresh all folders",
                        detail: "Rereads every folder and redraws the icons. For when an app's icon has changed."
                    ) {
                        PillIconButton(
                            systemImage: "arrow.triangle.2.circlepath",
                            backgroundColor: .white,
                            iconColor: .black,
                            rotation: refreshSpinAngle
                        ) {
                            withAnimation(.interpolatingSpring(stiffness: 40, damping: 5)) {
                                refreshSpinAngle += 360
                            }
                            store.refreshAll()
                        }
                        .help("Refresh all folders")
                    }

                    if store.hasAnyCustomLabels() {
                        optionRow(
                            "Reset app names",
                            titleStyle: AnyShapeStyle(AppColors.brand),
                            detail: "Removes the names you typed in every folder. Each app gets its own name back."
                        ) {
                            PillIconButton(
                                systemImage: "arrow.counterclockwise",
                                backgroundColor: AppColors.brand,
                                iconColor: .white
                            ) {
                                showResetNamesAlert = true
                            }
                            .help("Reset all custom app names")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    /// One option: its title and control on a line, fine print underneath.
    /// The fine print stops short of the control column so it never runs under
    /// a switch or pill. It keeps the secondary colour and gets its hierarchy
    /// from size alone: anything dimmer falls below 4.5:1 at 10pt on the
    /// sidebar background.
    private func optionRow<Control: View>(
        _ title: String,
        titleStyle: AnyShapeStyle = AnyShapeStyle(.secondary),
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(titleStyle)
                Spacer()
                control()
                    .frame(width: Self.trailingControlWidth, alignment: .trailing)
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, Self.trailingControlWidth + 8)
        }
    }

}

struct NewFolderSheet: View {
    @Binding var isPresented: Bool
    var selectedFolder: Binding<DockFolder?>?
    @Environment(FolderStore.self) private var store
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
