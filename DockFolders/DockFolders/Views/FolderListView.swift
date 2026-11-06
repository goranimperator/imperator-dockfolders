import SwiftUI

struct FolderListView: View {
    @Environment(FolderStore.self) private var store
    @Binding var selectedFolder: DockFolder?
    @State private var folderToDelete: DockFolder?
    @State private var editingFolder: DockFolder?
    @State private var editedName: String = ""
    @State private var hoveredFolder: String?
    @FocusState private var isRenameFieldFocused: Bool

    /// Display order as folder ids. Follows the store, except while a row is
    /// lifted, when it is the live order the other rows slide into.
    @State private var order: [String] = []
    @State private var lifted: LiftedRow?
    /// Height of one row including its gaps. Measured off a rendered row; the
    /// starting value is that measurement on macOS 27.
    @State private var rowPitch: CGFloat = 51

    private struct LiftedRow {
        let id: String
        /// Pointer position in the list's coordinate space.
        var pointerY: CGFloat
        /// Pointer minus row centre when lifted, so the row stays where it was
        /// grabbed instead of jumping to centre on the pointer.
        let grab: CGFloat
        let startOrder: [String]
    }

    private static let space = "folderList"
    /// The same settle as the app grid, so both reorders feel like one thing.
    private static let settle = Animation.spring(response: 0.32, dampingFraction: 0.8)

    /// Whitespace around a row's fill: at the sidebar edges and between rows.
    private static let gap: CGFloat = 8
    /// Where the row's content sits, matching the settings rows above the list.
    private static let contentMargin: CGFloat = 20

    var body: some View {
        // Positioned rows in a scroll view rather than a List. A List reorders
        // through a system drag session: a translucent snapshot follows the
        // pointer and an insertion line shows the target, while the rows stay
        // put until the drop. Here the row itself lifts and the others slide
        // out of its way, the same as in the app grid. This departs from
        // BrandBook 7.18 (.onMove) on purpose.
        GeometryReader { geo in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(orderedFolders) { folder in
                        row(folder)
                            .frame(width: geo.size.width)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if height > 0 && abs(height - rowPitch) > 0.5 { rowPitch = height }
                            }
                            .scaleEffect(lifted?.id == folder.id ? 1.03 : 1)
                            .shadow(
                                color: .black.opacity(lifted?.id == folder.id ? 0.45 : 0),
                                radius: lifted?.id == folder.id ? 12 : 0,
                                y: lifted?.id == folder.id ? 6 : 0
                            )
                            .position(x: geo.size.width / 2, y: centerY(of: folder))
                            .zIndex(lifted?.id == folder.id ? 1 : 0)
                            // Animates the lift and, on release, the glide into
                            // the slot. While held the row tracks the pointer.
                            .animation(Self.settle, value: lifted?.id == folder.id)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
                                    .onChanged { value in drag(folder, value) }
                                    .onEnded { _ in drop() },
                                including: editingFolder == folder ? .subviews : .all
                            )
                            .accessibilityAction(named: "Move Up") { move(folder, by: -1) }
                            .accessibilityAction(named: "Move Down") { move(folder, by: 1) }
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width, height: CGFloat(orderedFolders.count) * rowPitch + Self.gap)
                .coordinateSpace(name: Self.space)
            }
        }
        .frame(minWidth: 200)
        .onAppear { order = store.folders.map(\.id) }
        .onChange(of: store.folders.map(\.id)) { _, ids in
            // Adding, deleting, renaming and a committed reorder land here.
            guard lifted == nil, ids != order else { return }
            withAnimation(Self.settle) { order = ids }
        }
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

    /// One folder row: grip, glyph, name and count, the Dock indicator and the
    /// trash that appears on hover.
    private func row(_ folder: DockFolder) -> some View {
        let isSelected = selectedFolder == folder
        return HStack(spacing: 10) {
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
        // Outer padding: the visible whitespace around the fill.
        .padding(.horizontal, Self.gap)
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
    }

    private var orderedFolders: [DockFolder] {
        let byId = Dictionary(store.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [DockFolder] = []
        for id in order {
            if let folder = byId[id], seen.insert(id).inserted { result.append(folder) }
        }
        for folder in store.folders where seen.insert(folder.id).inserted { result.append(folder) }
        return result
    }

    private func centerY(of folder: DockFolder) -> CGFloat {
        if let lifted, lifted.id == folder.id {
            return lifted.pointerY - lifted.grab
        }
        let index = order.firstIndex(of: folder.id) ?? order.count
        return Self.gap / 2 + (CGFloat(index) + 0.5) * rowPitch
    }

    private func drag(_ folder: DockFolder, _ value: DragGesture.Value) {
        if lifted == nil {
            lifted = LiftedRow(
                id: folder.id,
                pointerY: value.startLocation.y,
                grab: value.startLocation.y - centerY(of: folder),
                startOrder: order
            )
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        guard var current = lifted, current.id == folder.id else { return }
        current.pointerY = value.location.y
        lifted = current

        let rowCenter = current.pointerY - current.grab
        let target = min(max(Int(((rowCenter - Self.gap / 2) / rowPitch).rounded(.down)), 0), order.count - 1)
        if let from = order.firstIndex(of: folder.id), from != target {
            withAnimation(Self.settle) {
                order.remove(at: from)
                order.insert(folder.id, at: target)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func drop() {
        guard let current = lifted else { return }
        withAnimation(Self.settle) { lifted = nil }
        if order != current.startOrder { commitOrder() }
    }

    /// Keyboard and VoiceOver path: the List this replaced had none either,
    /// but a row that only a pointer can move is a control half finished.
    private func move(_ folder: DockFolder, by step: Int) {
        guard let from = order.firstIndex(of: folder.id) else { return }
        let to = min(max(from + step, 0), order.count - 1)
        guard to != from else { return }
        withAnimation(Self.settle) {
            order.remove(at: from)
            order.insert(folder.id, at: to)
        }
        commitOrder()
    }

    private func commitOrder() {
        let byId = Dictionary(store.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        store.reorderFolders(to: order.compactMap { byId[$0] })
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
