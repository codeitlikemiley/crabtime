import AppKit
import SwiftUI

struct WorkspaceSidebarToolbar: View {
    var body: some View {
        WorkspacePaletteButton()
    }
}

private struct WorkspacePaletteButton: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        Button(action: store.showWorkspacePalette) {
            HStack(spacing: 8) {
                Image(systemName: sourceKindSymbol(currentRecord?.sourceKind))
                    .font(.system(size: 11, weight: .semibold))

                Text(currentRecord?.displayTitle ?? AppBrand.shortName)
                    .lineLimit(1)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CrabTimeTheme.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(CrabTimeTheme.Palette.buttonFill)
            )
            .overlay {
                Capsule()
                    .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }

    private var currentRecord: SavedWorkspaceRecord? {
        store.currentWorkspaceRecord
    }

    private func sourceKindSymbol(_ kind: WorkspaceSourceKind?) -> String {
        switch kind {
        case .cloned:
            "arrow.down.circle"
        case .exercism:
            "graduationcap.circle"
        case .codeCrafters:
            "hammer.circle"
        default:
            "folder"
        }
    }
}

struct WorkspaceCommandPaletteView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @FocusState private var isSearchFocused: Bool
    @State private var selectedRootPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            searchSection
            workspaceResultsSection
        }
        .padding(18)
        .frame(width: 420)
        .background(CrabTimeTheme.Palette.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CrabTimeTheme.Palette.strongDivider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 12)
        .task(id: store.workspacePickerFocusToken) {
            guard store.isWorkspacePickerPresented else {
                return
            }
            syncSelectionToVisibleResults()
            isSearchFocused = true
        }
        .onAppear {
            syncSelectionToVisibleResults()
            isSearchFocused = true
        }
        .onChange(of: store.workspacePickerSearchText) { _, _ in
            syncSelectionToVisibleResults()
        }
        .onMoveCommand { direction in
            guard isSearchFocused, store.isWorkspacePickerPresented else {
                return
            }

            switch direction {
            case .down:
                moveSelectionDown()
            case .up:
                moveSelectionUp()
            default:
                break
            }
        }
        .background(
            WorkspacePaletteKeyBridge(
                isEnabled: isSearchFocused && store.isWorkspacePickerPresented,
                onMoveUp: moveSelectionUp,
                onMoveDown: moveSelectionDown,
                onActivate: { activateSelectedWorkspace(openInNewTab: false) },
                onActivateInNewTab: { activateSelectedWorkspace(openInNewTab: true) }
            )
        )
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspaces")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)

                Text("Search imported, cloned, and Exercism exercise libraries.")
                    .font(.footnote)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
            }

            Spacer()

            Button(action: store.hideWorkspacePalette) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(CrabTimeTheme.Palette.buttonFill))
            }
            .buttonStyle(.plain)
            .interactivePointer()
        }
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)

            TextField("Search workspaces", text: Binding(
                get: { store.workspacePickerSearchText },
                set: { store.workspacePickerSearchText = $0 }
            ))
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .foregroundStyle(CrabTimeTheme.Palette.ink)
            .tint(CrabTimeTheme.Palette.panelTint)
            .onSubmit {
                activateSelectedWorkspace(openInNewTab: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .fill(CrabTimeTheme.Palette.raisedFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }

    private var workspaceResultsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if store.filteredWorkspaceLibrary.isEmpty {
                    Text("No matching workspaces")
                        .font(.footnote)
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    ForEach(store.filteredWorkspaceLibrary) { record in
                        workspaceRow(for: record)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    @ViewBuilder
    private func workspaceRow(for record: SavedWorkspaceRecord) -> some View {
        Button {
            selectedRootPath = record.rootPath
            activateSelectedWorkspace(openInNewTab: false)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: sourceKindSymbol(record.sourceKind))
                    .foregroundStyle(isSelected(record) ? CrabTimeTheme.Palette.panelTint : CrabTimeTheme.Palette.textMuted)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.ink)

                    Text(record.rootURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if record.rootPath == currentRecord?.rootPath {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected(record) ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected(record) ? CrabTimeTheme.Palette.strongDivider : CrabTimeTheme.Palette.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .interactivePointer()
        .disabled(record.isMissing)
    }

    private var currentRecord: SavedWorkspaceRecord? {
        store.currentWorkspaceRecord
    }

    private func sourceKindSymbol(_ kind: WorkspaceSourceKind) -> String {
        switch kind {
        case .cloned:
            "arrow.down.circle.fill"
        case .exercism:
            "graduationcap.circle.fill"
        case .codeCrafters:
            "hammer.circle.fill"
        case .created:
            "plus.square.fill"
        case .imported:
            "folder.fill"
        }
    }

    private func isSelected(_ record: SavedWorkspaceRecord) -> Bool {
        record.rootPath == selectedRootPath
    }

    private func syncSelectionToVisibleResults() {
        if let selectedRootPath,
           store.filteredWorkspaceLibrary.contains(where: { $0.rootPath == selectedRootPath }) {
            return
        }

        selectedRootPath = store.filteredWorkspaceLibrary.first?.rootPath
    }

    private func moveSelectionUp() {
        guard !store.filteredWorkspaceLibrary.isEmpty else {
            return
        }

        let currentIndex = store.filteredWorkspaceLibrary.firstIndex(where: { $0.rootPath == selectedRootPath }) ?? 0
        let nextIndex = currentIndex == 0 ? store.filteredWorkspaceLibrary.count - 1 : currentIndex - 1
        selectedRootPath = store.filteredWorkspaceLibrary[nextIndex].rootPath
    }

    private func moveSelectionDown() {
        guard !store.filteredWorkspaceLibrary.isEmpty else {
            return
        }

        let currentIndex = store.filteredWorkspaceLibrary.firstIndex(where: { $0.rootPath == selectedRootPath }) ?? -1
        let nextIndex = (currentIndex + 1) % store.filteredWorkspaceLibrary.count
        selectedRootPath = store.filteredWorkspaceLibrary[nextIndex].rootPath
    }

    private func activateSelectedWorkspace(openInNewTab: Bool) {
        guard let rootPath = selectedRootPath ?? store.filteredWorkspaceLibrary.first?.rootPath else {
            return
        }

        if openInNewTab {
            openWindow(value: WorkspaceSceneRequest(rootPath: rootPath))
            store.hideWorkspacePalette()
        } else {
            store.loadPersistedWorkspace(rootPath: rootPath)
        }
    }
}

private struct WorkspacePaletteKeyBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onActivate: () -> Void
    let onActivateInNewTab: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onActivate: onActivate,
            onActivateInNewTab: onActivateInNewTab,
            isEnabled: isEnabled
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onActivate = onActivate
        context.coordinator.onActivateInNewTab = onActivateInNewTab
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        fileprivate var onMoveUp: () -> Void
        fileprivate var onMoveDown: () -> Void
        fileprivate var onActivate: () -> Void
        fileprivate var onActivateInNewTab: () -> Void
        fileprivate var isEnabled: Bool
        private weak var hostView: NSView?
        private var monitor: Any?

        init(
            onMoveUp: @escaping () -> Void,
            onMoveDown: @escaping () -> Void,
            onActivate: @escaping () -> Void,
            onActivateInNewTab: @escaping () -> Void,
            isEnabled: Bool
        ) {
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onActivate = onActivate
            self.onActivateInNewTab = onActivateInNewTab
            self.isEnabled = isEnabled
        }

        func attach(to view: NSView) {
            hostView = view
            if monitor == nil {
                startMonitoring()
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }

                let isHostWindowKey = self.hostView?.window?.isKeyWindow == true

                guard isHostWindowKey else {
                    return event
                }

                guard self.isEnabled else {
                    return event
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let characters = event.charactersIgnoringModifiers?.lowercased()

                if modifiers == [.command, .shift], [36, 76].contains(event.keyCode) {
                    self.onActivateInNewTab()
                    return nil
                }

                if modifiers == .control, characters == "n" {
                    self.onMoveDown()
                    return nil
                }

                if modifiers == .control, characters == "p" {
                    self.onMoveUp()
                    return nil
                }

                return event
            }
        }
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

                if store.supportsTestExerciseFilter {
                    DifficultyFilterChip(
                        title: "Tests",
                        tint: CrabTimeTheme.Palette.cyan,
                        isSelected: store.showsOnlyTestExercises
                    ) {
                        store.toggleTestsExerciseFilter()
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? CrabTimeTheme.Palette.ink : CrabTimeTheme.Palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? CrabTimeTheme.Palette.selectionFill : CrabTimeTheme.Palette.buttonFill)
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? CrabTimeTheme.Palette.strongDivider : CrabTimeTheme.Palette.divider, lineWidth: 1)
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? CrabTimeTheme.Palette.ink : tint.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? tint.opacity(0.18) : CrabTimeTheme.Palette.buttonFill)
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? tint.opacity(0.7) : CrabTimeTheme.Palette.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }
}
