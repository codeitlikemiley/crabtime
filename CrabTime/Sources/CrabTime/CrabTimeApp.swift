import AppKit
import SwiftUI

final class CrabTimeAppDelegate: NSObject, NSApplicationDelegate {
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
            do {
                database = try WorkspaceLibraryDatabase(paths: .temporary(rootName: "\(AppBrand.fallbackStoragePrefix)-\(UUID().uuidString)"))
            } catch {
                do {
                    database = try WorkspaceLibraryDatabase(paths: nil)
                } catch {
                    fatalError("Critical: SQLite in-memory database failed to open: \(error)")
                }
            }
        }

        let aiSettingsStore = AISettingsStore()
        self.aiSettingsStore = aiSettingsStore
        modelCatalogStore = AIModelCatalogStore()
        providerManager = AIProviderManager(
            settingsStore: aiSettingsStore,
            credentialStore: CredentialStore(),
            appPaths: appPaths
        )
    }
}

private struct FocusedWorkspaceStoreKey: FocusedValueKey {
    typealias Value = WorkspaceStore
}


struct FocusedNavigationStoreKey: FocusedValueKey {
    typealias Value = NavigationStore
}

extension FocusedValues {
    var navigationStore: NavigationStore? {
        get { self[FocusedNavigationStoreKey.self] }
        set { self[FocusedNavigationStoreKey.self] = newValue }
    }

    var workspaceStore: WorkspaceStore? {
        get { self[FocusedWorkspaceStoreKey.self] }
        set { self[FocusedWorkspaceStoreKey.self] = newValue }
    }
    var exercismStore: ExercismStore? {
        get { self[FocusedExercismStoreKey.self] }
        set { self[FocusedExercismStoreKey.self] = newValue }
    }
    var processStore: ProcessStore? {
        get { self[FocusedProcessStoreKey.self] }
        set { self[FocusedProcessStoreKey.self] = newValue }
    }
}

private struct FocusedExercismStoreKey: FocusedValueKey { typealias Value = ExercismStore }
private struct FocusedProcessStoreKey: FocusedValueKey { typealias Value = ProcessStore }

@MainActor
struct WorkspaceSceneRoot: View {
    let services: AppServices
    let initialWorkspaceRootPath: String?

    @State private var workspaceStore: WorkspaceStore
    @State private var chatStore: ChatStore
    @State private var todoStore: TodoExplorerStore
    @State private var exercismStore: ExercismStore
    @State private var processStore: ProcessStore
    @State private var editorStore: EditorStateStore
    @State private var explorerStore: ExplorerStore
    @State private var navigationStore: NavigationStore
    @State private var submissionService: ExerciseSubmissionService
    @State private var didApplyInitialWorkspace = false

    init(services: AppServices, initialWorkspaceRootPath: String? = nil) {
        self.services = services
        self.initialWorkspaceRootPath = initialWorkspaceRootPath

        let editorStore = EditorStateStore()
        let explorerStore = ExplorerStore()

        let workspaceStore = WorkspaceStore(
            appPaths: services.appPaths,
            database: services.database,
            editorStore: editorStore,
            explorerStore: explorerStore
        )
        let chatStore = ChatStore(
            database: services.database,
            providerManager: services.providerManager
        )
        let todoStore = TodoExplorerStore()
        let exercismStore = ExercismStore()
        let processStore = ProcessStore()
        workspaceStore.attachChatStore(chatStore)
        chatStore.attachProcessStore(processStore)

        _workspaceStore = State(initialValue: workspaceStore)
        _chatStore = State(initialValue: chatStore)
        _todoStore = State(initialValue: todoStore)
        _exercismStore = State(initialValue: exercismStore)
        _processStore = State(initialValue: processStore)
        _editorStore = State(initialValue: editorStore)
        _explorerStore = State(initialValue: explorerStore)
        _navigationStore = State(initialValue: NavigationStore())
        _submissionService = State(initialValue: ExerciseSubmissionService())
    }

    @State private var dependencyManager = DependencyManager.shared

    var body: some View {
        Group {
            if dependencyManager.status == .ready {
                MainSplitView()
                    .environment(workspaceStore)
                    .environment(chatStore)
                    .environment(todoStore)
                    .environment(exercismStore)
                    .environment(processStore)
                    .environment(editorStore)
                    .environment(explorerStore)
                    .environment(services.aiSettingsStore)
                    .environment(services.modelCatalogStore)
                    .environment(navigationStore)
                    .environment(submissionService)
                    
                    .focusedSceneValue(\.workspaceStore, workspaceStore)
                    .focusedSceneValue(\.navigationStore, navigationStore)
                    .focusedSceneValue(\.exercismStore, exercismStore)
                    .focusedSceneValue(\.processStore, processStore)
                    .task(id: initialWorkspaceRootPath) {
                        guard !didApplyInitialWorkspace else {
                            return
                        }

                        didApplyInitialWorkspace = true

                        if let initialWorkspaceRootPath {
                            workspaceStore.loadPersistedWorkspace(rootPath: initialWorkspaceRootPath)
                        }
                    }
            } else {
                SetupWizardView(
                    status: dependencyManager.status,
                    onInstall: {
                        Task { await dependencyManager.installMissingDependencies() }
                    }
                )
                .task {
                    await dependencyManager.checkDependencies()
                }
            }
        }
        .frame(minWidth: 1360, minHeight: 860)
        .preferredColorScheme(.dark)
    }
}

@MainActor
struct CrabTimeAppCommands: Commands {
    @FocusedValue(\.workspaceStore) private var workspaceStore
    @FocusedValue(\.navigationStore) private var navigationStore
    @FocusedValue(\.exercismStore) private var exercismStore
    @FocusedValue(\.processStore) private var processStore

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

            Button("Download Exercism Exercise…") {
                if let store = workspaceStore, let processStore = processStore {
                    exercismStore?.showExercismDownloadPrompt(using: store, processStore: processStore)
                }
            }
                .disabled(exercismStore == nil || workspaceStore == nil)

            Button("Check Exercism Setup") { exercismStore?.showExercismStatus() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(exercismStore == nil)

            Divider()

            SettingsLink {
                Text("Settings…")
            }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Run") {
            Button("Run Exercise") {
                if let processStore = processStore {
                    workspaceStore?.runSelectedExercise(processStore: processStore)
                }
            }
            .keyboardShortcut("R", modifiers: [.command])

            Button("Run Tests") {
                if let processStore = processStore {
                    workspaceStore?.runSelectedExerciseTests(processStore: processStore)
                }
            }
            .keyboardShortcut("U", modifiers: [.command])
        }

        CommandMenu("Workspace") {
            Button("Save Exercise") { workspaceStore?.saveSelectedExercise() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(workspaceStore?.hasSelection ?? false))

            Button("Close File") { workspaceStore?.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(workspaceStore?.currentOpenTabs.isEmpty ?? true)

            Button("Override Cargo Runner…") { workspaceStore?.showCommandPalette(with: "> ") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Submit to Exercism") { if let store = workspaceStore, let ps = processStore { exercismStore?.submitSelectedExerciseToExercism(using: store, processStore: ps) } }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!(workspaceStore.map { exercismStore?.canSubmitSelectedExerciseToExercism(using: $0) ?? false } ?? false))

            Divider()

            Button("Reset Workspace…") { workspaceStore?.resetCurrentWorkspace() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!(workspaceStore?.canResetCurrentWorkspace ?? false))

            Button("Delete Workspace…") { workspaceStore?.deleteCurrentWorkspace() }
                .keyboardShortcut(.deleteForward, modifiers: [.command, .shift])
                .disabled(!(workspaceStore?.canDeleteCurrentWorkspace ?? false))
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Left Column") {
                navigationStore?.toggleLeftColumnVisibility()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(workspaceStore == nil)

            Button("Toggle Right Sidebar") {
                navigationStore?.toggleRightSidebarVisibility()
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

            Button("Show File Explorer") { 
                if navigationStore?.contentDisplayMode == .editorMaximized {
                    navigationStore?.toggleLeftColumnVisibility()
                }
                navigationStore?.sidebarMode = .explorer
                workspaceStore?.showExplorerAndFocusSearch() 
            }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Focus Exercise Search") { 
                if navigationStore?.contentDisplayMode == .editorMaximized {
                    navigationStore?.toggleLeftColumnVisibility()
                }
                navigationStore?.sidebarMode = .exercises
                workspaceStore?.showExerciseLibraryAndFocusSearch() 
            }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Focus Exercism Catalog") { 
                if navigationStore?.contentDisplayMode == .editorMaximized {
                    navigationStore?.toggleLeftColumnVisibility()
                }
                navigationStore?.sidebarMode = .exercism
                workspaceStore?.showExercismCatalogAndFocusSearch() 
            }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(workspaceStore == nil)

            Button("Toggle Terminal") {
                navigationStore?.toggleTerminalVisibility()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(workspaceStore == nil)

            Button("Maximize Terminal") {
                navigationStore?.toggleTerminalMaximize()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(workspaceStore == nil)

            Button("Clear Output") { workspaceStore?.clearConsoleOutput() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(workspaceStore == nil)

            Button("Show Output Tab") {
                navigationStore?.selectedConsoleTab = .output
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(workspaceStore == nil)

            Button("Show Diagnostics Tab") {
                navigationStore?.selectedConsoleTab = .diagnostics
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(workspaceStore == nil)

            Button("Show Session Tab") {
                navigationStore?.selectedConsoleTab = .session
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(workspaceStore == nil)

            Button("Show TODO Explorer") { 
                if navigationStore?.contentDisplayMode == .editorMaximized {
                    navigationStore?.toggleLeftColumnVisibility()
                }
                navigationStore?.sidebarMode = .todos
                workspaceStore?.showTodoAndFocus() 
            }
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
struct CrabTimeApp: App {
    @NSApplicationDelegateAdaptor(CrabTimeAppDelegate.self) private var appDelegate
    private let services = AppServices()

    var body: some Scene {
        WindowGroup(AppBrand.shortName, for: WorkspaceSceneRequest.self) { request in
            WorkspaceSceneRoot(
                services: services,
                initialWorkspaceRootPath: request.wrappedValue?.rootPath
            )
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1640, height: 980)
        .commands {
            CrabTimeAppCommands()
        }

        Settings {
            AppSettingsView()
                .environment(services.aiSettingsStore)
                .environment(services.modelCatalogStore)
                    
                .preferredColorScheme(.dark)
        }
    }
}
