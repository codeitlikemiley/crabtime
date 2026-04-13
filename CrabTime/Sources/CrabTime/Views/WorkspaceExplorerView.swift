import AppKit
import SwiftUI

struct WorkspaceExplorerView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Explorer")

                    Text(store.workspace?.title ?? "Workspace Files")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CrabTimeTheme.Palette.ink)

                    Text("Browse the imported folder tree and open any file in the main workspace preview.")
                        .font(.footnote)
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                WorkspaceSidebarToolbar()
            }

            ExplorerSearchField(
                text: Binding(
                    get: { store.explorerSearchText },
                    set: { store.explorerSearchText = $0 }
                ),
                resultCount: store.visibleExplorerFileCount
            )

            if store.currentFileTree.isEmpty {
                WorkspaceEmptyStateView(
                    title: "No Files Loaded",
                    systemImage: "folder",
                    description: "Import a Rust folder to inspect its file tree here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.currentFileTree) { node in
                            WorkspaceExplorerNodeView(node: node, depth: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        store.setExplorerKeyboardFocus(active: true)
                    }
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            ExplorerKeyEventBridge(
                isEnabled: navigationStore.sidebarMode == .explorer && store.explorerKeyboardFocusActive,
                onKeyPress: { key in
                    store.handleExplorerKey(key)
                },
                onActivate: {
                    store.activateSelectedExplorerEntry()
                }
            )
        )
        .paneCard()
    }
}

private struct ExplorerSearchField: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Binding var text: String
    let resultCount: Int
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)

            TextField("Search files", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(CrabTimeTheme.Palette.ink)
                .tint(CrabTimeTheme.Palette.panelTint)
                .focused($isFocused)
                .onSubmit {
                    store.activateSelectedExplorerEntry()
                }

            Text("\(resultCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
        }
        .onChange(of: text) { _, _ in
            store.persistExplorerSearchTextChange()
        }
        .task(id: store.explorerSearchFocusToken) {
            guard store.explorerSearchFocusToken > 0 else {
                return
            }
            isFocused = true
        }
        .background(
            ExplorerSearchKeyBridge(
                isEnabled: isFocused,
                onMoveUp: store.moveExplorerSelectionUp,
                onMoveDown: store.moveExplorerSelectionDown,
                onActivate: store.activateSelectedExplorerEntry,
                onDismiss: {
                    isFocused = false
                    text = ""
                    store.setExplorerKeyboardFocus(active: true)
                }
            )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .fill(CrabTimeTheme.Palette.raisedFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrabTimeTheme.Layout.subpanelRadius, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }
}

private struct ExplorerSearchKeyBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onActivate: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMoveUp: onMoveUp, onMoveDown: onMoveDown, onActivate: onActivate, onDismiss: onDismiss, isEnabled: isEnabled)
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
        context.coordinator.onDismiss = onDismiss
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator: @unchecked Sendable {
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onActivate: () -> Void
        var onDismiss: () -> Void
        var isEnabled: Bool
        private weak var hostView: NSView?
        private var monitor: Any?

        init(onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onActivate: @escaping () -> Void, onDismiss: @escaping () -> Void, isEnabled: Bool) {
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onActivate = onActivate
            self.onDismiss = onDismiss
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
                guard let self else { return event }
                guard self.isEnabled, self.hostView?.window?.isKeyWindow == true else {
                    return event
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers?.lowercased()

                if modifiers.isEmpty, event.keyCode == 125 {
                    self.onMoveDown()
                    return nil
                }

                if modifiers.isEmpty, event.keyCode == 126 {
                    self.onMoveUp()
                    return nil
                }

                if modifiers == .control, chars == "n" {
                    self.onMoveDown()
                    return nil
                }

                if modifiers == .control, chars == "p" {
                    self.onMoveUp()
                    return nil
                }

                if modifiers.isEmpty, [36, 76].contains(event.keyCode) {
                    self.onActivate()
                    return nil
                }

                // Escape → dismiss search
                if modifiers.isEmpty, event.keyCode == 53 {
                    MainActor.assumeIsolated {
                        self.onDismiss()
                    }
                    return nil
                }

                return event
            }
        }
    }
}

private struct WorkspaceExplorerNodeView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore

    let node: WorkspaceFileNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if node.isDirectory {
                Button {
                    store.toggleExplorerDirectory(node)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                        Image(systemName: "folder")
                            .foregroundStyle(CrabTimeTheme.Palette.panelTint)

                        Text(node.name)
                            .foregroundStyle(CrabTimeTheme.Palette.ink)

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(rowBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(rowBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .interactivePointer()

                if isExpanded {
                    ForEach(node.children) { child in
                        WorkspaceExplorerNodeView(
                            node: child,
                            depth: depth + 1
                        )
                    }
                }
            } else {
                Button {
                    store.selectExplorerNode(node)
                    store.openExplorerFile(node.url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .foregroundStyle(fileTint)

                        Text(node.name)
                            .foregroundStyle(CrabTimeTheme.Palette.ink)
                            .lineLimit(1)

                        if store.isEnriching(exerciseURL: node.url) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(CrabTimeTheme.Palette.ember)
                        }

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14 + 24)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(rowBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(store.isEnriching(exerciseURL: node.url)
                                ? CrabTimeTheme.Palette.ember.opacity(0.45)
                                : rowBorder,
                                lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .interactivePointer()
            }
        }
    }

    private var isExpanded: Bool {
        let isFiltering = !store.explorerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isFiltering || store.expandedExplorerDirectoryPaths.contains(node.url.standardizedFileURL.path)
    }

    private var isSelected: Bool {
        store.selectedExplorerNodePath == node.url.standardizedFileURL.path
            || store.selectedExplorerFileURL?.standardizedFileURL == node.url.standardizedFileURL
    }

    private var fileTint: Color {
        isSelected ? CrabTimeTheme.Palette.panelTint : CrabTimeTheme.Palette.textMuted
    }

    private var rowBorder: Color {
        isSelected ? CrabTimeTheme.Palette.strongDivider : .clear
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? CrabTimeTheme.Palette.selectionFill : Color.clear)
    }
}

private struct ExplorerKeyEventBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyPress: (String) -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyPress: onKeyPress, onActivate: onActivate)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.startMonitoring(isEnabled: isEnabled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyPress = onKeyPress
        context.coordinator.onActivate = onActivate
        context.coordinator.startMonitoring(isEnabled: isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator: @unchecked Sendable {
        var onKeyPress: (String) -> Void
        var onActivate: () -> Void
        private var monitor: Any?
        private var isEnabled = false

        init(onKeyPress: @escaping (String) -> Void, onActivate: @escaping () -> Void) {
            self.onKeyPress = onKeyPress
            self.onActivate = onActivate
        }

        func startMonitoring(isEnabled: Bool) {
            guard self.isEnabled != isEnabled else {
                return
            }

            self.isEnabled = isEnabled

            if isEnabled {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else {
                        return event
                    }

                    guard self.isEnabled else {
                        return event
                    }

                    let isTextEditing = MainActor.assumeIsolated {
                        NSApp.keyWindow?.firstResponder is NSTextView
                    }
                    guard !isTextEditing else {
                        return event
                    }

                    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let chars = event.charactersIgnoringModifiers?.lowercased()

                    // h/j/k/l vim keys
                    if modifiers.isEmpty,
                       let characters = chars,
                       ["h", "j", "k", "l"].contains(characters) {
                        self.onKeyPress(characters)
                        return nil
                    }

                    // Arrow keys
                    if modifiers.isEmpty {
                        if event.keyCode == 125 { // Down
                            self.onKeyPress("j")
                            return nil
                        }
                        if event.keyCode == 126 { // Up
                            self.onKeyPress("k")
                            return nil
                        }
                        if event.keyCode == 123 { // Left
                            self.onKeyPress("h")
                            return nil
                        }
                        if event.keyCode == 124 { // Right
                            self.onKeyPress("l")
                            return nil
                        }
                    }

                    // Ctrl+N/P
                    if modifiers == .control, chars == "n" {
                        self.onKeyPress("j")
                        return nil
                    }
                    if modifiers == .control, chars == "p" {
                        self.onKeyPress("k")
                        return nil
                    }

                    // Enter/Return → open selected file
                    if modifiers.isEmpty, [36, 76].contains(event.keyCode) {
                        MainActor.assumeIsolated {
                            self.onActivate()
                        }
                        return nil
                    }

                    return event
                }
            } else {
                stopMonitoring()
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            isEnabled = false
        }
    }
}
