import XCTest
@testable import RustGoblin

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    func testSaveSelectedExerciseUpdatesWorkspaceAndSourceFile() throws {
        let fileManager = FileManager.default
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge")
        let tempRootURL = try makeTemporaryWorkspaceRoot()
        let tempWorkspaceURL = tempRootURL.appendingPathComponent("sample_challenge")
        let appPaths = AppStoragePaths(baseURL: tempRootURL.appendingPathComponent("app-state", isDirectory: true))

        try fileManager.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        let store = WorkspaceStore(appPaths: appPaths)
        store.importWorkspace(from: tempWorkspaceURL)

        XCTAssertEqual(store.selectedExercise?.sourceURL.lastPathComponent, "challenge.rs")

        store.editorText = """
        fn main() {
            println!("patched");
        }
        """
        store.saveSelectedExercise()

        let managedWorkspaceURL = try XCTUnwrap(store.currentWorkspaceRecord?.rootURL)

        let savedSource = try String(
            contentsOf: managedWorkspaceURL.appendingPathComponent("challenge.rs"),
            encoding: .utf8
        )

        XCTAssertTrue(savedSource.contains("println!(\"patched\")"))
        XCTAssertEqual(store.selectedExercise?.sourceCode, savedSource)
        XCTAssertFalse(store.isEditorDirty)
    }

    func testOpenExplorerFileLoadsPreviewContent() throws {
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge")
        let tempRootURL = try makeTemporaryWorkspaceRoot()
        let tempWorkspaceURL = tempRootURL.appendingPathComponent("sample_challenge")
        let appPaths = AppStoragePaths(baseURL: tempRootURL.appendingPathComponent("app-state", isDirectory: true))
        try FileManager.default.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let store = WorkspaceStore(appPaths: appPaths)

        store.importWorkspace(from: tempWorkspaceURL)
        store.selectSidebarMode(.explorer)
        let managedWorkspaceURL = try XCTUnwrap(store.currentWorkspaceRecord?.rootURL)
        let managedReadmeURL = managedWorkspaceURL.appendingPathComponent("README.md")
        store.openExplorerFile(managedReadmeURL)

        XCTAssertEqual(store.selectedExplorerFileURL, managedReadmeURL)
        XCTAssertTrue(store.explorerPreviewText.contains("Sample Challenge"))
        XCTAssertTrue(store.isShowingExplorerPreview)
        XCTAssertTrue(store.isShowingReadonlyPreview)
        XCTAssertTrue(store.currentOpenFiles.contains(managedReadmeURL))
    }

    func testSelectExerciseRegistersSourceAsOpenTab() throws {
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge")
        let tempRootURL = try makeTemporaryWorkspaceRoot()
        let tempWorkspaceURL = tempRootURL.appendingPathComponent("sample_challenge")
        let appPaths = AppStoragePaths(baseURL: tempRootURL.appendingPathComponent("app-state", isDirectory: true))
        try FileManager.default.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }
        let store = WorkspaceStore(appPaths: appPaths)

        store.importWorkspace(from: tempWorkspaceURL)

        XCTAssertEqual(store.currentOpenFiles.first?.lastPathComponent, "challenge.rs")
    }

    func testWorkspaceStateRestoresAcrossLaunches() throws {
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge")
        let tempRootURL = try makeTemporaryWorkspaceRoot()
        let tempWorkspaceURL = tempRootURL.appendingPathComponent("sample_challenge")
        let appPaths = AppStoragePaths(baseURL: tempRootURL.appendingPathComponent("app-state", isDirectory: true))

        try FileManager.default.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let firstStore = WorkspaceStore(appPaths: appPaths)
        firstStore.importWorkspace(from: tempWorkspaceURL)
        firstStore.selectSidebarMode(.explorer)
        firstStore.searchText = "sample"
        firstStore.persistSearchTextChange()
        let managedWorkspaceURL = try XCTUnwrap(firstStore.currentWorkspaceRecord?.rootURL)
        let managedReadmeURL = managedWorkspaceURL.appendingPathComponent("README.md")
        firstStore.openExplorerFile(managedReadmeURL)

        let restoredStore = WorkspaceStore(appPaths: appPaths)

        XCTAssertEqual(restoredStore.workspaceLibrary.count, 1)
        XCTAssertEqual(restoredStore.currentWorkspaceRecord?.rootPath, managedWorkspaceURL.standardizedFileURL.path)
        XCTAssertEqual(restoredStore.selectedExercise?.sourceURL.lastPathComponent, "challenge.rs")
        XCTAssertEqual(restoredStore.selectedExplorerFileURL, managedReadmeURL)
        XCTAssertEqual(restoredStore.sidebarMode, .explorer)
        XCTAssertEqual(restoredStore.searchText, "sample")
        XCTAssertNil(restoredStore.selectedDifficultyFilter)
        XCTAssertEqual(restoredStore.currentOpenTabs.map(\.title), ["challenge.rs", "README.md"])
    }

    func testSearchFilterAppliesToVisibleExercises() throws {
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/rustlings_like")
        let tempRootURL = try makeTemporaryWorkspaceRoot()
        let tempWorkspaceURL = tempRootURL.appendingPathComponent("rustlings_like")
        let appPaths = AppStoragePaths(baseURL: tempRootURL.appendingPathComponent("app-state", isDirectory: true))

        try FileManager.default.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let store = WorkspaceStore(appPaths: appPaths)
        store.importWorkspace(from: tempWorkspaceURL)

        XCTAssertEqual(store.visibleExercises.count, 2)

        store.searchText = "two"
        store.persistSearchTextChange()
        XCTAssertEqual(store.visibleExercises.map(\.title), ["Variables Two"])

        store.searchText = ""
        store.persistSearchTextChange()
        XCTAssertEqual(store.visibleExercises.map(\.title), ["Variables One", "Variables Two"])
    }

    func testAIRuntimeEventsUpdateStructuredState() {
        let store = WorkspaceStore(appPaths: .temporary(rootName: UUID().uuidString))

        store.handleAITransportEvent(
            .transportSelected(provider: .geminiCLI, transport: .acp, model: "gemini-2.5-pro")
        )
        store.handleAITransportEvent(
            .sessionReady(
                provider: .geminiCLI,
                transport: .acp,
                sessionID: "session-123",
                reused: false,
                logFilePath: "/tmp/acp.log"
            )
        )
        store.handleAITransportEvent(
            .toolCall(provider: .geminiCLI, id: "tool-1", title: "Read file", status: "completed")
        )

        XCTAssertEqual(store.aiRuntimeProviderTitle, AIProviderKind.geminiCLI.title)
        XCTAssertEqual(store.aiRuntimeTransport, .acp)
        XCTAssertEqual(store.aiRuntimeModel, "gemini-2.5-pro")
        XCTAssertEqual(store.aiRuntimeSessionID, "session-123")
        XCTAssertEqual(store.aiRuntimeAuthStatus, "Ready")
        XCTAssertEqual(store.aiRuntimeLogPath, "/tmp/acp.log")
        XCTAssertEqual(store.aiRuntimeToolCalls.first?.title, "Read file")
        XCTAssertEqual(store.aiRuntimeToolCalls.first?.status, "completed")
        XCTAssertFalse(store.aiRuntimeEvents.isEmpty)
    }

    func testAIRuntimeErrorUpdatesFailureState() {
        let store = WorkspaceStore(appPaths: .temporary(rootName: UUID().uuidString))

        store.handleAITransportEvent(
            .transportError(provider: .openCodeCLI, message: "ACP process exited", logFilePath: "/tmp/opencode.log")
        )

        XCTAssertEqual(store.aiRuntimeProviderTitle, AIProviderKind.openCodeCLI.title)
        XCTAssertEqual(store.aiRuntimeProcessStatus, "Failed")
        XCTAssertEqual(store.aiRuntimeLastError, "ACP process exited")
        XCTAssertEqual(store.aiRuntimeLogPath, "/tmp/opencode.log")
    }

    func testResetSelectedWarmSessionClearsBackendSessionID() throws {
        let defaults = UserDefaults(suiteName: "WorkspaceStoreTests.reset.\(UUID().uuidString)")!
        let appPaths = AppStoragePaths.temporary(rootName: UUID().uuidString)
        let database = try WorkspaceLibraryDatabase(paths: appPaths)
        let settingsStore = AISettingsStore(defaults: defaults)
        let providerManager = AIProviderManager(
            settingsStore: settingsStore,
            credentialStore: CredentialStore(),
            appPaths: appPaths
        )
        let store = WorkspaceStore(appPaths: appPaths, database: database, defaults: defaults)
        let chatStore = ChatStore(database: database, providerManager: providerManager)
        store.attachChatStore(chatStore)

        let session = ExerciseChatSession(
            workspaceRootPath: "/tmp/workspace",
            exercisePath: "/tmp/workspace/exercise.rs",
            title: "Reset Session",
            providerKind: .geminiCLI,
            model: "gemini-2.5-pro",
            backendSessionID: "warm-123"
        )

        try database.upsertChatSession(session)
        chatStore.sessions = [session]
        chatStore.selectedSessionID = session.id

        chatStore.resetSelectedWarmSession(using: store)

        XCTAssertNil(chatStore.selectedSession?.backendSessionID)
        let fetched = try database.fetchChatSessions(
            workspaceRootPath: session.workspaceRootPath,
            exercisePath: session.exercisePath
        )
        XCTAssertNil(fetched.first?.backendSessionID)
    }

    func testNonRustlingsWorkspaceHidesRustlingsOnlyDifficultyFilters() throws {
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge")
        let tempRootURL = try makeTemporaryWorkspaceRoot()
        let tempWorkspaceURL = tempRootURL.appendingPathComponent("sample_challenge")
        let appPaths = AppStoragePaths(baseURL: tempRootURL.appendingPathComponent("app-state", isDirectory: true))

        try FileManager.default.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let store = WorkspaceStore(appPaths: appPaths)
        store.importWorkspace(from: tempWorkspaceURL)

        XCTAssertEqual(store.availableDifficultyFilters, [])
        XCTAssertFalse(store.showsDifficultyFilters)
    }

    func testModifiedWorkspaceRelativePathsReflectSavedEditsAgainstLoadBaseline() throws {
        let fileManager = FileManager.default
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge")
        let tempRootURL = try makeTemporaryWorkspaceRoot()
        let tempWorkspaceURL = tempRootURL.appendingPathComponent("sample_challenge")
        let appPaths = AppStoragePaths(baseURL: tempRootURL.appendingPathComponent("app-state", isDirectory: true))

        try fileManager.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        let store = WorkspaceStore(appPaths: appPaths)
        store.importWorkspace(from: tempWorkspaceURL)

        XCTAssertEqual(store.modifiedWorkspaceRelativePaths, [])

        store.editorText = """
        fn main() {
            println!("patched");
        }
        """
        store.saveSelectedExercise()

        XCTAssertEqual(store.modifiedWorkspaceRelativePaths, ["challenge.rs"])
    }

    private func makeTemporaryWorkspaceRoot() throws -> URL {
        let tempRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true)
        return tempRootURL
    }
}
