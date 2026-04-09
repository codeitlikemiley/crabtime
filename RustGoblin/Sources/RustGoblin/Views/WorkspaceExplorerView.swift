import AppKit
import SwiftUI

struct WorkspaceExplorerView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Explorer")

                    Text(store.workspace?.title ?? "Workspace Files")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RustGoblinTheme.Palette.ink)

                    Text("Browse the imported folder tree and open any file in the main workspace preview.")
                        .font(.footnote)
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
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
                isEnabled: store.sidebarMode == .explorer && store.explorerKeyboardFocusActive,
                onKeyPress: { key in
                    store.handleExplorerKey(key)
                }
            )
        )
        .paneCard()
    }
}

private struct ExplorerSearchField: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var text: String
    let resultCount: Int
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RustGoblinTheme.Palette.textMuted)

            TextField("Search files", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(RustGoblinTheme.Palette.ink)
                .tint(RustGoblinTheme.Palette.panelTint)
                .focused($isFocused)
                .onSubmit {
                    store.activateSelectedExplorerEntry()
                }

            Text("\(resultCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RustGoblinTheme.Palette.panelTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(RustGoblinTheme.Palette.buttonFill))
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
                onActivate: store.activateSelectedExplorerEntry
            )
        )
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
    }
}

private struct ExplorerSearchKeyBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMoveUp: onMoveUp, onMoveDown: onMoveDown, onActivate: onActivate, isEnabled: isEnabled)
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
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onActivate: () -> Void
        var isEnabled: Bool
        private weak var hostView: NSView?
        private var monitor: Any?

        init(onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onActivate: @escaping () -> Void, isEnabled: Bool) {
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onActivate = onActivate
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

                return event
            }
        }
    }
}

private struct WorkspaceExplorerNodeView: View {
    @Environment(WorkspaceStore.self) private var store

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
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)

                        Image(systemName: "folder")
                            .foregroundStyle(RustGoblinTheme.Palette.panelTint)

                        Text(node.name)
                            .foregroundStyle(RustGoblinTheme.Palette.ink)

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
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14 + 24)
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
        isSelected ? RustGoblinTheme.Palette.panelTint : RustGoblinTheme.Palette.textMuted
    }

    private var rowBorder: Color {
        isSelected ? RustGoblinTheme.Palette.strongDivider : .clear
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? RustGoblinTheme.Palette.selectionFill : Color.clear)
    }
}

private struct ExplorerKeyEventBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyPress: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyPress: onKeyPress)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.startMonitoring(isEnabled: isEnabled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyPress = onKeyPress
        context.coordinator.startMonitoring(isEnabled: isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        var onKeyPress: (String) -> Void
        private var monitor: Any?
        private var isEnabled = false

        init(onKeyPress: @escaping (String) -> Void) {
            self.onKeyPress = onKeyPress
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

                    guard self.isEnabled,
                          event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                          let characters = event.charactersIgnoringModifiers?.lowercased(),
                          ["h", "j", "k", "l"].contains(characters) else {
                        return event
                    }

                    let isTextEditing = MainActor.assumeIsolated {
                        NSApp.keyWindow?.firstResponder is NSTextView
                    }
                    guard !isTextEditing else {
                        return event
                    }

                    self.onKeyPress(characters)
                    return nil
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
