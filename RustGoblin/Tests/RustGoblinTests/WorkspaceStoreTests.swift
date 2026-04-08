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

        let savedSource = try String(
            contentsOf: tempWorkspaceURL.appendingPathComponent("challenge.rs"),
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
        let readmeURL = tempWorkspaceURL.appendingPathComponent("README.md")
        try FileManager.default.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let store = WorkspaceStore(appPaths: appPaths)

        store.importWorkspace(from: tempWorkspaceURL)
        store.selectSidebarMode(.explorer)
        store.openExplorerFile(tempWorkspaceURL.appendingPathComponent("README.md"))

        XCTAssertEqual(store.selectedExplorerFileURL, tempWorkspaceURL.appendingPathComponent("README.md"))
        XCTAssertTrue(store.explorerPreviewText.contains("Sample Challenge"))
        XCTAssertTrue(store.isShowingExplorerPreview)
        XCTAssertTrue(store.isShowingReadonlyPreview)
        XCTAssertTrue(store.currentOpenFiles.contains(readmeURL))
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
        let readmeURL = tempWorkspaceURL.appendingPathComponent("README.md")

        try FileManager.default.copyItem(at: fixtureURL, to: tempWorkspaceURL)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let firstStore = WorkspaceStore(appPaths: appPaths)
        firstStore.importWorkspace(from: tempWorkspaceURL)
        firstStore.selectSidebarMode(.explorer)
        firstStore.searchText = "sample"
        firstStore.persistSearchTextChange()
        firstStore.selectDifficultyFilter(.core)
        firstStore.openExplorerFile(readmeURL)

        let restoredStore = WorkspaceStore(appPaths: appPaths)

        XCTAssertEqual(restoredStore.workspaceLibrary.count, 1)
        XCTAssertEqual(restoredStore.currentWorkspaceRecord?.rootPath, tempWorkspaceURL.standardizedFileURL.path)
        XCTAssertEqual(restoredStore.selectedExercise?.sourceURL.lastPathComponent, "challenge.rs")
        XCTAssertEqual(restoredStore.selectedExplorerFileURL, readmeURL)
        XCTAssertEqual(restoredStore.sidebarMode, .explorer)
        XCTAssertEqual(restoredStore.searchText, "sample")
        XCTAssertNil(restoredStore.selectedDifficultyFilter)
        XCTAssertEqual(restoredStore.currentOpenTabs.map(\.title), ["challenge.rs", "README.md"])
    }

    func testSearchAndDifficultyFilterApplyToVisibleExercises() throws {
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
        store.selectDifficultyFilter(.easy)
        XCTAssertEqual(store.visibleExercises.map(\.title), ["Variables One"])
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
