import SwiftUI

@MainActor
struct ExercismBrowserView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(NavigationStore.self) private var navigationStore
    @Environment(ExercismStore.self) private var store
    @Environment(ProcessStore.self) private var processStore
    @FocusState private var isSearchFocused: Bool

    @MainActor
    private func toggleFilter(_ filter: String?) {
        guard let filter else {
            store.exercismFilters.removeAll()
            return
        }
        
        if store.exercismFilters.contains(filter) {
            store.exercismFilters.remove(filter)
        } else {
            store.exercismFilters.insert(filter)
        }
    }

    var body: some View {
        @Bindable var store = store
        let workspaceStore = workspaceStore
        let processStore = processStore
        let navigationStore = navigationStore
        
        let credentialStore = CredentialStore()
        let hasToken = !(credentialStore.readSecret(for: "exercism_api_token") ?? "").isEmpty

        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel(text: "Exercism Catalog")

                Text("Rust Track")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CrabTimeTheme.Palette.ink)

                Text("Browse, search, and download Rust exercises directly into isolated workspaces.")
                    .font(.footnote)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !hasToken {
                VStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                    
                    Text("API Token Required")
                        .font(.headline)
                    
                    Text("Please configure your Exercism API Token in Settings to browse and download exercises.")
                        .font(.footnote)
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if store.isLoadingExercismExercises {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading catalog...")
                        .font(.footnote)
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Search Field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                    TextField("Search exercises", text: $store.exercismSearchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(CrabTimeTheme.Palette.ink)
                        .tint(CrabTimeTheme.Palette.panelTint)
                        .focused($isSearchFocused)
                        .background(
                            ExercismSearchKeyBridge(
                                isEnabled: isSearchFocused,
                                onMoveUp: store.moveExercismSelectionUp,
                                onMoveDown: store.moveExercismSelectionDown,
                                onActivate: { store.activateSelectedExercismExercise(using: workspaceStore, processStore: processStore) },
                                onDismiss: { isSearchFocused = false }
                            )
                        )

                    Text("\(store.visibleExercismExercises.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                }
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
                .task(id: workspaceStore.exercismSearchFocusToken) {
                    guard workspaceStore.exercismSearchFocusToken > 0 else { return }
                    isSearchFocused = true
                }

                // Filters
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    FilterBadge(title: "All", isSelected: store.exercismFilters.isEmpty) {
                        toggleFilter(nil)
                    }
                    FilterBadge(title: "Easy", isSelected: store.exercismFilters.contains("easy")) {
                        toggleFilter("easy")
                    }
                    FilterBadge(title: "Medium", isSelected: store.exercismFilters.contains("medium")) {
                        toggleFilter("medium")
                    }
                    FilterBadge(title: "Hard", isSelected: store.exercismFilters.contains("hard")) {
                        toggleFilter("hard")
                    }
                    FilterBadge(title: "Downloaded", isSelected: store.exercismFilters.contains("downloaded")) {
                        toggleFilter("downloaded")
                    }
                    FilterBadge(title: "Completed", isSelected: store.exercismFilters.contains("completed")) {
                        toggleFilter("completed")
                    }
                    
                    Button {
                        // Force refresh — empty clears the cache check
                        store.exercismExercises = []
                        Task { await store.fetchExercismCatalog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                            .padding(.leading, 4)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Catalog")
                }

                // List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(store.visibleExercismExercises.enumerated()), id: \.element.id) { index, exercise in
                                ExercismExerciseCard(
                                    exercise: exercise,
                                    isSelected: index == store.selectedExercismIndex,
                                    isDownloaded: store.exercismDownloadedExercises.contains(exercise.slug),
                                    isCompleted: store.exercismCompletedExercises.contains(exercise.slug),
                                    onDownload: {
                                        store.selectedExercismIndex = index
                                        store.activateSelectedExercismExercise(using: workspaceStore, processStore: processStore)
                                    }
                                )
                                .id(exercise.id)
                                .onTapGesture {
                                    store.selectedExercismIndex = index
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: store.selectedExercismIndex) { _, newValue in
                        let items = store.visibleExercismExercises
                        if items.indices.contains(newValue) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(items[newValue].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .paneCard()
        .background(
            ExercismKeyBridge(
                isEnabled: navigationStore.sidebarMode == .exercism,
                onMoveUp: store.moveExercismSelectionUp,
                onMoveDown: store.moveExercismSelectionDown,
                onActivate: { store.activateSelectedExercismExercise(using: workspaceStore, processStore: processStore) }
            )
        )
    }
}

@MainActor
private struct FilterBadge: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? CrabTimeTheme.Palette.ink : CrabTimeTheme.Palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? CrabTimeTheme.Palette.ember.opacity(0.25) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? CrabTimeTheme.Palette.ember.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }
}

@MainActor
private struct ExercismExerciseCard: View {
    let exercise: ExercismExercise
    let isSelected: Bool
    let isDownloaded: Bool
    let isCompleted: Bool
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if exercise.isUnlocked {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(CrabTimeTheme.Palette.moss)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                        }
                        
                        Text(exercise.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(CrabTimeTheme.Palette.ink)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        let difficultyColor: Color = {
                            switch exercise.difficulty {
                            case "easy": return CrabTimeTheme.Palette.moss
                            case "medium": return .orange
                            case "hard": return CrabTimeTheme.Palette.ember
                            default: return CrabTimeTheme.Palette.textMuted
                            }
                        }()
                        
                        Text(exercise.difficulty.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(difficultyColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(difficultyColor.opacity(0.15))
                            .clipShape(Capsule())

                        if isCompleted {
                            Text("COMPLETED")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(CrabTimeTheme.Palette.moss)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CrabTimeTheme.Palette.moss.opacity(0.15))
                                .clipShape(Capsule())
                        } else if isDownloaded {
                            Text("DOWNLOADED")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(CrabTimeTheme.Palette.panelTint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CrabTimeTheme.Palette.panelTint.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        
                        if exercise.isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(CrabTimeTheme.Palette.cyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CrabTimeTheme.Palette.cyan.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        
                        Text(exercise.type.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                    }
                }
                Spacer()
            }
            
            Text(exercise.blurb)
                .font(.footnote)
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Spacer()
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Download")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(CrabTimeTheme.Palette.panelFill)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CrabTimeTheme.Palette.ink))
                }
                .buttonStyle(.plain)
                .interactivePointer()
                .opacity(isSelected ? 1.0 : 0.8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? CrabTimeTheme.Palette.ember.opacity(0.1) : CrabTimeTheme.Palette.raisedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? CrabTimeTheme.Palette.ember.opacity(0.4) : CrabTimeTheme.Palette.divider, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Keyboard Bridge

@MainActor
private struct ExercismKeyBridge: NSViewRepresentable {
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

                if modifiers.isEmpty, (chars == "d") {
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

@MainActor
private struct ExercismSearchKeyBridge: NSViewRepresentable {
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

                if modifiers.isEmpty, (chars == "d") {
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
