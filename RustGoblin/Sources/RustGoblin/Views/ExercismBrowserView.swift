import SwiftUI

struct ExercismBrowserView: View {
    @Environment(WorkspaceStore.self) private var store
    @FocusState private var isSearchFocused: Bool

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
        
        let credentialStore = CredentialStore()
        let hasToken = !(credentialStore.readSecret(for: "exercism_api_token") ?? "").isEmpty

        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel(text: "Exercism Catalog")

                Text("Rust Track")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(RustGoblinTheme.Palette.ink)

                Text("Browse, search, and download Rust exercises directly into isolated workspaces.")
                    .font(.footnote)
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !hasToken {
                VStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(RustGoblinTheme.Palette.panelTint)
                    
                    Text("API Token Required")
                        .font(.headline)
                    
                    Text("Please configure your Exercism API Token in Settings to browse and download exercises.")
                        .font(.footnote)
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
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
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Search Field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(RustGoblinTheme.Palette.textMuted)

                    TextField("Search exercises", text: $store.exercismSearchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(RustGoblinTheme.Palette.ink)
                        .tint(RustGoblinTheme.Palette.panelTint)
                        .focused($isSearchFocused)

                    Text("\(store.visibleExercismExercises.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RustGoblinTheme.Palette.panelTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(RustGoblinTheme.Palette.buttonFill))
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
                .task(id: store.exercismSearchFocusToken) {
                    guard store.exercismSearchFocusToken > 0 else { return }
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
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
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
                                        store.activateSelectedExercismExercise()
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
                isEnabled: store.sidebarMode == .exercism,
                onMoveUp: store.moveExercismSelectionUp,
                onMoveDown: store.moveExercismSelectionDown,
                onActivate: store.activateSelectedExercismExercise
            )
        )
    }
}

private struct FilterBadge: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? RustGoblinTheme.Palette.ink : RustGoblinTheme.Palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? RustGoblinTheme.Palette.ember.opacity(0.25) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? RustGoblinTheme.Palette.ember.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .interactivePointer()
    }
}

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
                                .foregroundStyle(RustGoblinTheme.Palette.moss)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                        }
                        
                        Text(exercise.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(RustGoblinTheme.Palette.ink)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        let difficultyColor: Color = {
                            switch exercise.difficulty {
                            case "easy": return RustGoblinTheme.Palette.moss
                            case "medium": return .orange
                            case "hard": return RustGoblinTheme.Palette.ember
                            default: return RustGoblinTheme.Palette.textMuted
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
                                .foregroundStyle(RustGoblinTheme.Palette.moss)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RustGoblinTheme.Palette.moss.opacity(0.15))
                                .clipShape(Capsule())
                        } else if isDownloaded {
                            Text("DOWNLOADED")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(RustGoblinTheme.Palette.panelTint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RustGoblinTheme.Palette.panelTint.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        
                        if exercise.isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(RustGoblinTheme.Palette.cyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RustGoblinTheme.Palette.cyan.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        
                        Text(exercise.type.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    }
                }
                Spacer()
            }
            
            Text(exercise.blurb)
                .font(.footnote)
                .foregroundStyle(RustGoblinTheme.Palette.textMuted)
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
                    .foregroundStyle(RustGoblinTheme.Palette.panelFill)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(RustGoblinTheme.Palette.ink))
                }
                .buttonStyle(.plain)
                .interactivePointer()
                .opacity(isSelected ? 1.0 : 0.8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? RustGoblinTheme.Palette.ember.opacity(0.1) : RustGoblinTheme.Palette.raisedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? RustGoblinTheme.Palette.ember.opacity(0.4) : RustGoblinTheme.Palette.divider, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Keyboard Bridge

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
