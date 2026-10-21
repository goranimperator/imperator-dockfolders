import SwiftUI

struct FolderListView: View {
    @EnvironmentObject var store: FolderStore
    @Binding var selectedFolder: DockFolder?
    @State private var folderToDelete: DockFolder?
    @State private var editingFolder: DockFolder?
    @State private var editedName: String = ""
    @State private var hoveredFolder: String?
    @FocusState private var isRenameFieldFocused: Bool

    /// Whitespace around a row's fill: at the sidebar edges and between rows.
    private static let gap: CGFloat = 8
    /// Where the row's content sits, matching the settings rows above the list.
    private static let contentMargin: CGFloat = 20
    /// Where the row box lands inside the sidebar, measured on macOS 27 with
    /// listRowInsets zeroed. The trailing side is wider because of the
    /// scroller gutter. The outer padding below is what is left to reach
    /// Self.gap, so one re-measure fixes the row if AppKit changes them.
    private static let boxInsetLeading: CGFloat = 8
    private static let boxInsetTrailing: CGFloat = 9.5

    var body: some View {
        // No selection: binding. The list's own highlight draws the full row
        // width behind listRowBackground, so the brand pill (inset 6pt) left a
        // lighter ring of system highlight showing around it. Selection is set
        // on tap instead, and the pill is the only thing that draws it.
        List {
            ForEach(store.folders) { folder in
                // Everything in a selected row goes white: the brand red fill is
                // dark enough that .secondary and .tertiary disappear into it.
                let isSelected = selectedFolder == folder
                HStack(spacing: 10) {
                    DragGrip()
                        .help("Drag to reorder")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.gray))

                    // Same weight as the dock indicator on the trailing edge of
                    // the row, so both row glyphs read as one set, and the same
                    // height as the grip beside it.
                    FolderGlyph(size: DragGrip.height)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
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
                                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                            Text("\(folder.apps.count) apps")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
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
                                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                            }

                            Button(action: { folderToDelete = folder }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                            }
                            // .plain, not .borderless: borderless tints the
                            // label with the accent colour, so the trash came
                            // out a different colour from the dock indicator
                            // beside it.
                            .buttonStyle(.plain)
                            .help("Delete")
                            .frame(width: isHovered ? nil : 0)
                            .opacity(isHovered ? 1 : 0)
                            .clipped()
                        }
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        hoveredFolder = hovering ? folder.id : nil
                    }
                }
                // Inner padding, inside the fill. Reaches the 20pt margin the
                // settings rows above the list use, so the grip lines up with
                // their labels and the dock indicator with their toggles.
                .padding(.leading, Self.contentMargin - Self.gap)
                .padding(.trailing, Self.contentMargin - Self.gap)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The fill rides on the content, not on listRowBackground: that
                // one is clipped to the row box, whose trailing edge the list
                // keeps a few points inside the sidebar, so the right margin
                // could never be made to match the left.
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AppColors.brand : Color.clear)
                )
                // Outer padding: whatever is left to make the visible
                // whitespace Self.gap on every side.
                .padding(.leading, Self.gap - Self.boxInsetLeading)
                .padding(.trailing, Self.gap - Self.boxInsetTrailing)
                .padding(.vertical, Self.gap / 2)
                // Hit testing goes last, so the whole padded row selects, not
                // just the area the labels happen to cover.
                .contentShape(Rectangle())
                .onTapGesture { selectedFolder = folder }
                .contextMenu {
                    Button(folder.isInDock ? "Remove from Dock" : "Add to Dock") {
                        store.toggleDock(for: folder)
                    }
                    Divider()
                    Button("Delete Folder", role: .destructive) {
                        folderToDelete = folder
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                // Paint the selection fill here rather than letting the list
                // draw it. The .sidebar style renders its tint through the
                // sidebar material, which lightens #A01818 into a salmon; this
                // puts the brand red down flat, edge to edge.
                .listRowBackground(Color.clear)
            }
            .onMove { from, to in
                var reordered = store.folders
                reordered.move(fromOffsets: from, toOffset: to)
                store.reorderFolders(to: reordered)
            }
        }
        // .plain, not .sidebar: the sidebar style draws its own highlight over
        // listRowBackground, so the brand fill above would never be the colour
        // actually seen.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.vertical, Self.gap / 2)
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
