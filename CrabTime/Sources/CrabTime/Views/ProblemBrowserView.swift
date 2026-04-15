import SwiftUI

@MainActor
struct ProblemBrowserView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore

    var body: some View {
        @Bindable var store = store

        Group {
            switch navigationStore.sidebarMode {
            case .explorer:
                WorkspaceExplorerView()
            case .todos:
                TodoExplorerView()
            case .exercism:
                ExercismBrowserView()
            case .exercises:
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        EyebrowLabel(text: "Exercise Library")

                        Text(store.workspace?.title ?? "Imported Exercises")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(CrabTimeTheme.Palette.ink)

                        Text("Browse imported prompts, switch between exercises, and keep the brief close to the code.")
                            .font(.footnote)
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ProblemSearchField(text: $store.searchText, resultCount: store.visibleExercises.count)
                    DifficultyFilterStrip()

                    ExerciseCatalogView()
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(
                    ExerciseListKeyBridge(
                        isEnabled: navigationStore.sidebarMode == .exercises && store.exerciseKeyboardFocusActive,
                        onMoveUp: store.moveExerciseSelectionUp,
                        onMoveDown: store.moveExerciseSelectionDown,
                        onActivate: store.openSelectedExerciseListIndex
                    )
                )
                .paneCard()
                .simultaneousGesture(
                    TapGesture().onEnded {
                        store.setExerciseKeyboardFocus(active: true)
                    }
                )
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if navigationStore.sidebarMode != .explorer {
                    store.setExplorerKeyboardFocus(active: false)
                }
                if navigationStore.sidebarMode != .exercises {
                    store.setExerciseKeyboardFocus(active: false)
                }
            }
        )
    }
}

@MainActor
private struct ProblemSearchField: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(NavigationStore.self) private var navigationStore
    @Binding var text: String
    let resultCount: Int
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)

            TextField("Search exercises", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(CrabTimeTheme.Palette.ink)
                .tint(CrabTimeTheme.Palette.panelTint)
                .focused($isFocused)
                .onSubmit {
                    store.openFirstVisibleExercise()
                }

            Text("\(resultCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
        }
        .onChange(of: text) { _, _ in
            store.persistSearchTextChange()
        }
        .task(id: store.exerciseSearchFocusToken) {
            guard store.exerciseSearchFocusToken > 0 else {
                return
            }
            isFocused = true
        }
        .background(
            ExerciseSearchKeyBridge(
                isEnabled: isFocused,
                onMoveUp: store.moveExerciseSelectionUp,
                onMoveDown: store.moveExerciseSelectionDown,
                onActivate: store.openSelectedExerciseListIndex,
                onDismiss: {
                    isFocused = false
                    store.setExerciseKeyboardFocus(active: true)
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

@MainActor
private struct ExerciseListKeyBridge: NSViewRepresentable {
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
                    NSApp.keyWindow?.firstResponder is NSTextView || NSApp.keyWindow?.firstResponder is NSTextField
                }
                guard !isTextEditing else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers?.lowercased()

                if modifiers.isEmpty, (chars == "j" || event.keyCode == 125) {
                    MainActor.assumeIsolated { self.onMoveDown() }
                    return nil
                }
                if modifiers == .control, chars == "n" {
                    MainActor.assumeIsolated { self.onMoveDown() }
                    return nil
                }

                if modifiers.isEmpty, (chars == "k" || event.keyCode == 126) {
                    MainActor.assumeIsolated { self.onMoveUp() }
                    return nil
                }
                if modifiers == .control, chars == "p" {
                    MainActor.assumeIsolated { self.onMoveUp() }
                    return nil
                }

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
            self.isEnabled = false
        }
    }
}

@MainActor
private struct ExerciseSearchKeyBridge: NSViewRepresentable {
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
