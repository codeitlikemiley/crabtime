import SwiftUI

struct TodoExplorerView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(TodoExplorerStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let workspaceStore = workspaceStore

        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel(text: "TODO Explorer")

                Text("Pending Tasks")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)

                Text("Jump to `todo!()`, `unimplemented!()`, TODO comments, and FIXME markers.")
                    .font(.footnote)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Search
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                    TextField("Filter TODOs…", text: $store.todoSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                Text("\(store.visibleTodoItems(using: workspaceStore).count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
            }

            // Scope filter
            HStack(spacing: 6) {
                scopeButton(title: "Workspace", isActive: !store.todoScopeCurrentFile) {
                    store.todoScopeCurrentFile = false
                    store.selectedTodoIndex = 0
                }
                scopeButton(title: "Current File", isActive: store.todoScopeCurrentFile) {
                    store.todoScopeCurrentFile = true
                    store.selectedTodoIndex = 0
                }

                Spacer()

                Button {
                    store.refreshTodoItems(using: workspaceStore)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("Refresh TODOs")
                .interactivePointer()
            }

            // List
            let items = store.visibleTodoItems(using: workspaceStore)
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(CrabTimeTheme.Palette.moss.opacity(0.6))

                    Text("No TODOs found")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                    Text(store.todoScopeCurrentFile
                         ? "This file has no pending items."
                         : "All clear across the workspace."
                    )
                    .font(.caption)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                TodoItemRow(
                                    item: item,
                                    isSelected: index == store.selectedTodoIndex
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.selectedTodoIndex = index
                                    store.activateTodoItem(item, using: workspaceStore)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: store.selectedTodoIndex) { _, newValue in
                        let visible = store.visibleTodoItems(using: workspaceStore)
                        if visible.indices.contains(newValue) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(visible[newValue].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .paneCard()
        .onAppear {
            store.refreshTodoItems(using: workspaceStore)
        }
        .background(
            TodoKeyBridge(
                isEnabled: workspaceStore.sidebarMode == .todos,
                onMoveUp: { store.moveTodoSelectionUp(using: workspaceStore) },
                onMoveDown: { store.moveTodoSelectionDown(using: workspaceStore) },
                onActivate: { store.activateSelectedTodo(using: workspaceStore) }
            )
        )
    }

    private func scopeButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? CrabTimeTheme.Palette.ink : CrabTimeTheme.Palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isActive ? CrabTimeTheme.Palette.ember.opacity(0.25) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? CrabTimeTheme.Palette.ember.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }
}

// MARK: - Todo Item Row

private struct TodoItemRow: View {
    let item: TodoItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.kind.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(CrabTimeTheme.Palette.cyan.opacity(0.8))

                    Text(":\(item.line)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                    Spacer()

                    Text(item.kind.label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(kindColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(kindColor.opacity(0.12))
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? CrabTimeTheme.Palette.ember.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? CrabTimeTheme.Palette.ember.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .interactivePointer()
    }

    private var iconColor: Color {
        switch item.kind {
        case .todoMacro: return CrabTimeTheme.Palette.ember
        case .todoComment, .todoDocComment: return CrabTimeTheme.Palette.cyan
        case .unimplemented: return .orange
        case .fixme: return .red
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .todoMacro: return CrabTimeTheme.Palette.ember
        case .todoComment, .todoDocComment: return CrabTimeTheme.Palette.cyan
        case .unimplemented: return .orange
        case .fixme: return .red
        }
    }
}

// MARK: - Keyboard Bridge

private struct TodoKeyBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMoveUp: onMoveUp, onMoveDown: onMoveDown, onActivate: onActivate)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onActivate = onActivate
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator: @unchecked Sendable {
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onActivate: () -> Void
        var isEnabled: Bool = true
        private var monitor: Any?

        init(onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onActivate: @escaping () -> Void) {
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onActivate = onActivate
        }

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }

                let isTextEditing = MainActor.assumeIsolated {
                    NSApp.keyWindow?.firstResponder is NSTextView
                }
                guard !isTextEditing else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers?.lowercased()

                // j or Arrow Down or Ctrl+N → move down
                if modifiers.isEmpty, (chars == "j" || event.keyCode == 125) {
                    MainActor.assumeIsolated { self.onMoveDown() }
                    return nil
                }
                if modifiers == .control, chars == "n" {
                    MainActor.assumeIsolated { self.onMoveDown() }
                    return nil
                }

                // k or Arrow Up or Ctrl+P → move up
                if modifiers.isEmpty, (chars == "k" || event.keyCode == 126) {
                    MainActor.assumeIsolated { self.onMoveUp() }
                    return nil
                }
                if modifiers == .control, chars == "p" {
                    MainActor.assumeIsolated { self.onMoveUp() }
                    return nil
                }

                // Enter/Return → activate
                if modifiers.isEmpty, [36, 76].contains(event.keyCode) {
                    MainActor.assumeIsolated { self.onActivate() }
                    return nil
                }

                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
