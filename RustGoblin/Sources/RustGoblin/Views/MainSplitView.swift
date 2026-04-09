import SwiftUI

struct MainSplitView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = store

        GeometryReader { proxy in
            HStack(alignment: .top, spacing: RustGoblinTheme.Layout.columnSpacing) {
                WorkspaceRailView()
                    .frame(width: RustGoblinTheme.Layout.sidebarWidth)

                ProblemBrowserView()
                    .frame(width: store.showsProblemPane ? problemWidth(in: proxy.size.width) : 0)
                    .opacity(store.showsProblemPane ? 1 : 0)
                    .allowsHitTesting(store.showsProblemPane)
                    .clipped()

                HStack(alignment: .top, spacing: RustGoblinTheme.Layout.columnSpacing) {
                    EditorWorkbenchView()
                        .frame(maxWidth: store.showsEditorPane ? .infinity : 0, maxHeight: .infinity)
                        .opacity(store.showsEditorPane ? 1 : 0)
                        .allowsHitTesting(store.showsEditorPane)
                        .clipped()

                    RightSidebarView()
                        .frame(width: store.showsInspector ? inspectorWidth(in: proxy.size.width) : 0)
                        .opacity(store.showsInspector ? 1 : 0)
                        .allowsHitTesting(store.showsInspector)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(layoutAnimation, value: store.contentDisplayMode)
            .animation(layoutAnimation, value: store.isInspectorVisible)
            .padding(RustGoblinTheme.Layout.outerPadding)
            .background(WorkbenchBackgroundView())
            .background(
                WindowTitleBridge(title: store.windowTitle)
            )
            .background(
                WindowCommandBridge(
                    shouldHandleCloseFile: !store.currentOpenTabs.isEmpty,
                    hasOpenTabs: !store.currentOpenTabs.isEmpty,
                    isWorkspacePalettePresented: store.isWorkspacePickerPresented,
                    canResetWorkspace: store.canResetCurrentWorkspace,
                    canDeleteWorkspace: store.canDeleteCurrentWorkspace,
                    onCloseFile: store.closeActiveTab,
                    onSelectPreviousTab: store.activatePreviousTab,
                    onSelectNextTab: store.activateNextTab,
                    onSelectNumberedTab: store.activateNumberedTab,
                    onResetWorkspace: store.resetCurrentWorkspace,
                    onDeleteWorkspace: store.deleteCurrentWorkspace,
                    onToggleWorkspacePalette: {
                        if store.isWorkspacePickerPresented {
                            store.hideWorkspacePalette()
                        } else {
                            store.showWorkspacePalette()
                        }
                    },
                    onDismissWorkspacePalette: store.hideWorkspacePalette
                )
            )
            .overlay {
                if store.isWorkspacePickerPresented {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.hideWorkspacePalette()
                            }

                        WorkspaceCommandPaletteView()
                            .environment(store)
                            .padding(.top, 56)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var layoutAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.16)
    }

    private func problemWidth(in totalWidth: CGFloat) -> CGFloat {
        min(RustGoblinTheme.Layout.problemWidth, max(312, totalWidth * 0.24))
    }

    private func inspectorWidth(in totalWidth: CGFloat) -> CGFloat {
        _ = totalWidth
        return RustGoblinTheme.Layout.inspectorWidth
    }
}

private struct WindowCommandBridge: NSViewRepresentable {
    let shouldHandleCloseFile: Bool
    let hasOpenTabs: Bool
    let isWorkspacePalettePresented: Bool
    let canResetWorkspace: Bool
    let canDeleteWorkspace: Bool
    let onCloseFile: () -> Void
    let onSelectPreviousTab: () -> Void
    let onSelectNextTab: () -> Void
    let onSelectNumberedTab: (Int) -> Void
    let onResetWorkspace: () -> Void
    let onDeleteWorkspace: () -> Void
    let onToggleWorkspacePalette: () -> Void
    let onDismissWorkspacePalette: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCloseFile: onCloseFile,
            onSelectPreviousTab: onSelectPreviousTab,
            onSelectNextTab: onSelectNextTab,
            onSelectNumberedTab: onSelectNumberedTab,
            onResetWorkspace: onResetWorkspace,
            onDeleteWorkspace: onDeleteWorkspace,
            onToggleWorkspacePalette: onToggleWorkspacePalette,
            onDismissWorkspacePalette: onDismissWorkspacePalette
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(
            shouldHandleCloseFile: shouldHandleCloseFile,
            hasOpenTabs: hasOpenTabs,
            isWorkspacePalettePresented: isWorkspacePalettePresented,
            canResetWorkspace: canResetWorkspace,
            canDeleteWorkspace: canDeleteWorkspace,
            onCloseFile: onCloseFile,
            onSelectPreviousTab: onSelectPreviousTab,
            onSelectNextTab: onSelectNextTab,
            onSelectNumberedTab: onSelectNumberedTab,
            onResetWorkspace: onResetWorkspace,
            onDeleteWorkspace: onDeleteWorkspace,
            onToggleWorkspacePalette: onToggleWorkspacePalette,
            onDismissWorkspacePalette: onDismissWorkspacePalette
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.update(
            shouldHandleCloseFile: shouldHandleCloseFile,
            hasOpenTabs: hasOpenTabs,
            isWorkspacePalettePresented: isWorkspacePalettePresented,
            canResetWorkspace: canResetWorkspace,
            canDeleteWorkspace: canDeleteWorkspace,
            onCloseFile: onCloseFile,
            onSelectPreviousTab: onSelectPreviousTab,
            onSelectNextTab: onSelectNextTab,
            onSelectNumberedTab: onSelectNumberedTab,
            onResetWorkspace: onResetWorkspace,
            onDeleteWorkspace: onDeleteWorkspace,
            onToggleWorkspacePalette: onToggleWorkspacePalette,
            onDismissWorkspacePalette: onDismissWorkspacePalette
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        private weak var hostView: NSView?
        private var monitor: Any?
        private var shouldHandleCloseFile = false
        private var hasOpenTabs = false
        private var isWorkspacePalettePresented = false
        private var canResetWorkspace = false
        private var canDeleteWorkspace = false
        private var onCloseFile: () -> Void
        private var onSelectPreviousTab: () -> Void
        private var onSelectNextTab: () -> Void
        private var onSelectNumberedTab: (Int) -> Void
        private var onResetWorkspace: () -> Void
        private var onDeleteWorkspace: () -> Void
        private var onToggleWorkspacePalette: () -> Void
        private var onDismissWorkspacePalette: () -> Void

        init(
            onCloseFile: @escaping () -> Void,
            onSelectPreviousTab: @escaping () -> Void,
            onSelectNextTab: @escaping () -> Void,
            onSelectNumberedTab: @escaping (Int) -> Void,
            onResetWorkspace: @escaping () -> Void,
            onDeleteWorkspace: @escaping () -> Void,
            onToggleWorkspacePalette: @escaping () -> Void,
            onDismissWorkspacePalette: @escaping () -> Void
        ) {
            self.onCloseFile = onCloseFile
            self.onSelectPreviousTab = onSelectPreviousTab
            self.onSelectNextTab = onSelectNextTab
            self.onSelectNumberedTab = onSelectNumberedTab
            self.onResetWorkspace = onResetWorkspace
            self.onDeleteWorkspace = onDeleteWorkspace
            self.onToggleWorkspacePalette = onToggleWorkspacePalette
            self.onDismissWorkspacePalette = onDismissWorkspacePalette
        }

        func attach(to view: NSView) {
            hostView = view
            if monitor == nil {
                startMonitoring()
            }
        }

        func update(
            shouldHandleCloseFile: Bool,
            hasOpenTabs: Bool,
            isWorkspacePalettePresented: Bool,
            canResetWorkspace: Bool,
            canDeleteWorkspace: Bool,
            onCloseFile: @escaping () -> Void,
            onSelectPreviousTab: @escaping () -> Void,
            onSelectNextTab: @escaping () -> Void,
            onSelectNumberedTab: @escaping (Int) -> Void,
            onResetWorkspace: @escaping () -> Void,
            onDeleteWorkspace: @escaping () -> Void,
            onToggleWorkspacePalette: @escaping () -> Void,
            onDismissWorkspacePalette: @escaping () -> Void
        ) {
            self.shouldHandleCloseFile = shouldHandleCloseFile
            self.hasOpenTabs = hasOpenTabs
            self.isWorkspacePalettePresented = isWorkspacePalettePresented
            self.canResetWorkspace = canResetWorkspace
            self.canDeleteWorkspace = canDeleteWorkspace
            self.onCloseFile = onCloseFile
            self.onSelectPreviousTab = onSelectPreviousTab
            self.onSelectNextTab = onSelectNextTab
            self.onSelectNumberedTab = onSelectNumberedTab
            self.onResetWorkspace = onResetWorkspace
            self.onDeleteWorkspace = onDeleteWorkspace
            self.onToggleWorkspacePalette = onToggleWorkspacePalette
            self.onDismissWorkspacePalette = onDismissWorkspacePalette
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

                let hostView = self.hostView
                let isHostWindowKey = MainActor.assumeIsolated {
                    guard let hostWindow = hostView?.window else {
                        return false
                    }
                    return hostWindow.isKeyWindow
                }

                guard isHostWindowKey else {
                    return event
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let characters = event.charactersIgnoringModifiers?.lowercased()

                if modifiers == .command, characters == "p" {
                    self.onToggleWorkspacePalette()
                    return nil
                }

                if self.isWorkspacePalettePresented,
                   modifiers.isEmpty,
                   event.keyCode == 53 {
                    self.onDismissWorkspacePalette()
                    return nil
                }

                if modifiers == .command, characters == "w", self.shouldHandleCloseFile {
                    self.onCloseFile()
                    return nil
                }

                if modifiers == [.command, .shift] {
                    if event.keyCode == 51, self.canResetWorkspace {
                        self.onResetWorkspace()
                        return nil
                    }

                    if event.keyCode == 117, self.canDeleteWorkspace {
                        self.onDeleteWorkspace()
                        return nil
                    }
                }

                if modifiers == .control {
                    if characters == "[" {
                        self.selectPreviousNativeTab()
                        return nil
                    }

                    if characters == "]" {
                        self.selectNextNativeTab()
                        return nil
                    }

                    if let characters,
                       let digit = Int(characters),
                       (0...9).contains(digit) {
                        self.selectNativeTab(number: digit)
                        return nil
                    }
                }

                if modifiers == .command, self.hasOpenTabs {
                    if characters == "[" {
                        self.onSelectPreviousTab()
                        return nil
                    }

                    if characters == "]" {
                        self.onSelectNextTab()
                        return nil
                    }

                    if let characters,
                       let digit = Int(characters),
                       (0...9).contains(digit) {
                        self.onSelectNumberedTab(digit)
                        return nil
                    }
                }

                return event
            }
        }

        private func selectPreviousNativeTab() {
            hostView?.window?.selectPreviousTab(nil)
        }

        private func selectNextNativeTab() {
            hostView?.window?.selectNextTab(nil)
        }

        private func selectNativeTab(number: Int) {
            guard let window = hostView?.window else {
                return
            }

            let tabbedWindows = window.tabbedWindows ?? [window]
            guard !tabbedWindows.isEmpty else {
                return
            }

            let index: Int
            if number == 0 {
                index = tabbedWindows.count - 1
            } else {
                index = number - 1
            }

            guard tabbedWindows.indices.contains(index) else {
                return
            }

            tabbedWindows[index].makeKeyAndOrderFront(nil)
        }
    }
}

private struct WindowTitleBridge: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateWindowTitle(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindowTitle(from: nsView)
    }

    private func updateWindowTitle(from view: NSView) {
        DispatchQueue.main.async {
            view.window?.title = title
        }
    }
}
