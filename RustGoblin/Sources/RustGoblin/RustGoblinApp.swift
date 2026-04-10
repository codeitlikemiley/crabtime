import AppKit
import SwiftUI

final class RustGoblinAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WorkspaceSceneRequest: Codable, Hashable {
    let rootPath: String
}

@MainActor
final class AppServices {
    let appPaths: AppStoragePaths
    let database: WorkspaceLibraryDatabase
    let aiSettingsStore: AISettingsStore
    let modelCatalogStore: AIModelCatalogStore
    let providerManager: AIProviderManager

    init() {
        appPaths = AppStoragePaths.live()

        do {
            database = try WorkspaceLibraryDatabase(paths: appPaths)
        } catch {
            database = try! WorkspaceLibraryDatabase(paths: .temporary(rootName: "RustGoblin-Fallback-\(UUID().uuidString)"))
        }

        let aiSettingsStore = AISettingsStore()
        self.aiSettingsStore = aiSettingsStore
        modelCatalogStore = AIModelCatalogStore()
        providerManager = AIProviderManager(
            settingsStore: aiSettingsStore,
            credentialStore: CredentialStore()
        )
    }
}

private struct FocusedWorkspaceStoreKey: FocusedValueKey {
    typealias Value = WorkspaceStore
}

extension FocusedValues {
    var workspaceStore: WorkspaceStore? {
        get { self[FocusedWorkspaceStoreKey.self] }
        set { self[FocusedWorkspaceStoreKey.self] = newValue }
    }
}

struct WorkspaceSceneRoot: View {
    let services: AppServices
    let initialWorkspaceRootPath: String?

    @State private var workspaceStore: WorkspaceStore
    @State private var chatStore: ChatStore
    @State private var didApplyInitialWorkspace = false

    init(services: AppServices, initialWorkspaceRootPath: String? = nil) {
        self.services = services
        self.initialWorkspaceRootPath = initialWorkspaceRootPath

        let workspaceStore = WorkspaceStore(
            appPaths: services.appPaths,
            database: services.database
        )
        let chatStore = ChatStore(
            database: services.database,
            providerManager: services.providerManager
        )
        workspaceStore.attachChatStore(chatStore)

        _workspaceStore = State(initialValue: workspaceStore)
        _chatStore = State(initialValue: chatStore)
    }

    var body: some View {
        MainSplitView()
            .environment(workspaceStore)
            .environment(chatStore)
            .environment(services.aiSettingsStore)
            .environment(services.modelCatalogStore)
            .frame(minWidth: 1360, minHeight: 860)
            .preferredColorScheme(.dark)
            .focusedSceneValue(\.workspaceStore, workspaceStore)
            .task(id: initialWorkspaceRootPath) {
                guard !didApplyInitialWorkspace else {
                    return
                }

                didApplyInitialWorkspace = true

                if let initialWorkspaceRootPath {
                    workspaceStore.loadPersistedWorkspace(rootPath: initialWorkspaceRootPath)
                }
            }
    }
}

struct RustGoblinAppCommands: Commands {
    @FocusedValue(\.workspaceStore) private var workspaceStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Workspace…") { workspaceStore?.showNewWorkspacePrompt() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(workspaceStore == nil)

            Divider()

            Button("Import Exercises…") { workspaceStore?.openWorkspace() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Clone Repository…") { workspaceStore?.showCloneSheet() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Divider()

            Button("Download Exercism Exercise…") { workspaceStore?.showExercismDownloadPrompt() }
                .disabled(workspaceStore == nil)

            Button("Check Exercism Setup") { workspaceStore?.showExercismStatus() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(workspaceStore == nil)

            Divider()

            SettingsLink {
                Text("Settings…")
            }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Workspace") {
            Button("Save Exercise") { workspaceStore?.saveSelectedExercise() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(workspaceStore?.hasSelection ?? false))

            Button("Close File") { workspaceStore?.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(workspaceStore?.currentOpenTabs.isEmpty ?? true)

            Button("Run Exercise") { workspaceStore?.runSelectedExercise() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!(workspaceStore?.hasSelection ?? false) || (workspaceStore?.isRunning ?? false))

            Button("Override Cargo Runner…") { workspaceStore?.showCommandPalette(with: "> ") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Submit to Exercism") { workspaceStore?.submitSelectedExerciseToExercism() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!(workspaceStore?.canSubmitSelectedExerciseToExercism ?? false))

            Divider()

            Button("Reset Workspace…") { workspaceStore?.resetCurrentWorkspace() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!(workspaceStore?.canResetCurrentWorkspace ?? false))

            Button("Delete Workspace…") { workspaceStore?.deleteCurrentWorkspace() }
                .keyboardShortcut(.deleteForward, modifiers: [.command, .shift])
                .disabled(!(workspaceStore?.canDeleteCurrentWorkspace ?? false))
        }

        CommandGroup(replacing: .sidebar) {
            Button(
                workspaceStore?.showsProblemPane ?? true ? "Hide Left Column" : "Show Left Column"
            ) {
                workspaceStore?.toggleLeftColumnVisibility()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(workspaceStore == nil)

            Button(
                workspaceStore?.isInspectorVisible ?? true ? "Hide Right Sidebar" : "Show Right Sidebar"
            ) {
                workspaceStore?.toggleRightSidebarVisibility()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(workspaceStore == nil)
        }

        // Remove macOS Print (Cmd+P) so we can use it for Command Palette
        CommandGroup(replacing: .printItem) { }

        CommandGroup(after: .toolbar) {
            Button("Open Workspace Palette") { workspaceStore?.showWorkspacePalette() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Command Palette") { workspaceStore?.showCommandPalette() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Show File Explorer") { workspaceStore?.showExplorerAndFocusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Focus Exercise Search") { workspaceStore?.showExerciseLibraryAndFocusSearch() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Focus Exercism Catalog") { workspaceStore?.showExercismCatalogAndFocusSearch() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button(workspaceStore?.showsTerminal ?? true ? "Hide Terminal" : "Show Terminal") {
                workspaceStore?.toggleTerminalVisibility()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(workspaceStore == nil)

            Button(workspaceStore?.isTerminalMaximized ?? false ? "Restore Terminal Layout" : "Maximize Terminal") {
                workspaceStore?.toggleTerminalMaximize()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(workspaceStore == nil)

            Button("Clear Output") { workspaceStore?.clearConsoleOutput() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Show Output Tab") { workspaceStore?.selectConsoleTab(.output) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Show Diagnostics Tab") { workspaceStore?.selectConsoleTab(.diagnostics) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Show Session Tab") { workspaceStore?.selectConsoleTab(.session) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Show TODO Explorer") { workspaceStore?.showTodoAndFocus() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Focus Exercise Chat") { workspaceStore?.focusChatComposer() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Focus Inspector List") { workspaceStore?.focusInspectorList() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)
        }
    }
}

@main
struct RustGoblinApp: App {
    @NSApplicationDelegateAdaptor(RustGoblinAppDelegate.self) private var appDelegate
    private let services = AppServices()

    var body: some Scene {
        WindowGroup("RustGoblin", for: WorkspaceSceneRequest.self) { request in
            WorkspaceSceneRoot(
                services: services,
                initialWorkspaceRootPath: request.wrappedValue?.rootPath
            )
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1640, height: 980)
        .commands {
            RustGoblinAppCommands()
        }

        Settings {
            AppSettingsView()
                .environment(services.aiSettingsStore)
                .environment(services.modelCatalogStore)
                .preferredColorScheme(.dark)
        }
    }
}
