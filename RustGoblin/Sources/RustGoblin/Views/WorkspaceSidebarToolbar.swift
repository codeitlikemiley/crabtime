import SwiftUI

struct WorkspaceSidebarToolbar: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            WorkspaceSwitcherMenu()
            WorkspaceActionMenu()
        }
    }
}

private struct WorkspaceSwitcherMenu: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        Button {
            store.isWorkspacePickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sourceKindSymbol(currentRecord?.sourceKind, filled: false))
                    .font(.system(size: 11, weight: .semibold))

                Text(currentRecord?.displayTitle ?? "No Workspace")
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(RustGoblinTheme.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(RustGoblinTheme.Palette.buttonFill)
            )
            .overlay {
                Capsule()
                    .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .interactivePointer()
        .popover(isPresented: Binding(
            get: { store.isWorkspacePickerPresented },
            set: { store.isWorkspacePickerPresented = $0 }
        ), arrowEdge: .top) {
            WorkspacePickerPopover()
                .environment(store)
        }
    }

    private var currentRecord: SavedWorkspaceRecord? {
        store.currentWorkspaceRecord
    }

    private func labelSymbol(for record: SavedWorkspaceRecord) -> String {
        if record.rootPath == currentRecord?.rootPath {
            return "checkmark"
        }

        return sourceKindSymbol(record.sourceKind, filled: false)
    }

    private func sourceKindSymbol(_ kind: WorkspaceSourceKind?, filled: Bool) -> String {
        switch kind {
        case .cloned:
            return filled ? "arrow.down.circle.fill" : "arrow.down.circle"
        case .exercism:
            return filled ? "graduationcap.circle.fill" : "graduationcap.circle"
        default:
            return filled ? "folder.fill" : "folder"
        }
    }
}

private struct WorkspacePickerPopover: View {
    @Environment(WorkspaceStore.self) private var store
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspaces")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(RustGoblinTheme.Palette.ink)

                Text("Search imported, cloned, and Exercism exercise libraries.")
                    .font(.footnote)
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)

                TextField("Search workspaces", text: Binding(
                    get: { store.workspacePickerSearchText },
                    set: { store.workspacePickerSearchText = $0 }
                ))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .foregroundStyle(RustGoblinTheme.Palette.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                    .fill(RustGoblinTheme.Palette.raisedFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: RustGoblinTheme.Layout.subpanelRadius, style: .continuous)
                    .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.filteredWorkspaceLibrary.isEmpty {
                        Text("No matching workspaces")
                            .font(.footnote)
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        ForEach(store.filteredWorkspaceLibrary) { record in
                            Button {
                                store.loadPersistedWorkspace(rootPath: record.rootPath)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: sourceKindSymbol(record.sourceKind, filled: true))
                                        .foregroundStyle(record.rootPath == currentRecord?.rootPath ? RustGoblinTheme.Palette.panelTint : RustGoblinTheme.Palette.textMuted)
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.displayTitle)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(RustGoblinTheme.Palette.ink)

                                        Text(record.rootURL.lastPathComponent)
                                            .font(.caption)
                                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if record.rootPath == currentRecord?.rootPath {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(RustGoblinTheme.Palette.panelTint)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(record.rootPath == currentRecord?.rootPath ? RustGoblinTheme.Palette.selectionFill : RustGoblinTheme.Palette.buttonFill)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(record.rootPath == currentRecord?.rootPath ? RustGoblinTheme.Palette.strongDivider : RustGoblinTheme.Palette.divider, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .interactivePointer()
                            .disabled(record.isMissing)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(16)
        .frame(width: 320)
        .background(RustGoblinTheme.Palette.panelFill)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var currentRecord: SavedWorkspaceRecord? {
        store.currentWorkspaceRecord
    }

    private func sourceKindSymbol(_ kind: WorkspaceSourceKind, filled: Bool) -> String {
        switch kind {
        case .cloned:
            return filled ? "arrow.down.circle.fill" : "arrow.down.circle"
        case .exercism:
            return filled ? "graduationcap.circle.fill" : "graduationcap.circle"
        case .imported:
            return filled ? "folder.fill" : "folder"
        }
    }
}

private struct WorkspaceActionMenu: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        Menu {
            Button("Import Exercises…", systemImage: "folder.badge.plus", action: store.openWorkspace)
            Button("Clone Repository…", systemImage: "arrow.down.doc", action: store.showCloneSheet)
            Divider()
            Button("Download Exercism Exercise…", systemImage: "graduationcap", action: store.showExercismDownloadPrompt)
            Button("Check Exercism Setup", systemImage: "checkmark.shield", action: store.showExercismStatus)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RustGoblinTheme.Palette.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(RustGoblinTheme.Palette.buttonFill)
                )
                .overlay {
                    Circle()
                        .stroke(RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .interactivePointer()
    }
}

struct DifficultyFilterStrip: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CompletionVisibilityChip(
                    title: "Open",
                    isSelected: store.completionFilter == .open
                ) {
                    store.selectCompletionFilter(.open)
                }

                CompletionVisibilityChip(
                    title: "Done",
                    isSelected: store.completionFilter == .done
                ) {
                    store.selectCompletionFilter(.done)
                }

                if store.showsDifficultyFilters {
                    DifficultyFilterChip(
                        title: "Any",
                        tint: RustGoblinTheme.Palette.cyan,
                        isSelected: store.selectedDifficultyFilter == nil
                    ) {
                        store.selectDifficultyFilter(nil)
                    }

                    ForEach(store.availableDifficultyFilters, id: \.self) { difficulty in
                        DifficultyFilterChip(
                            title: difficulty.title,
                            tint: difficulty.tint,
                            isSelected: store.selectedDifficultyFilter == difficulty
                        ) {
                            store.selectDifficultyFilter(difficulty)
                        }
                    }
                }
            }
        }
    }
}

private struct CompletionVisibilityChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? RustGoblinTheme.Palette.panelTint : RustGoblinTheme.Palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? RustGoblinTheme.Palette.selectionFill : RustGoblinTheme.Palette.buttonFill)
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? RustGoblinTheme.Palette.strongDivider : RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }
}

private struct DifficultyFilterChip: View {
    let title: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? tint : RustGoblinTheme.Palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? tint.opacity(0.12) : RustGoblinTheme.Palette.buttonFill)
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? tint.opacity(0.24) : RustGoblinTheme.Palette.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }
}
