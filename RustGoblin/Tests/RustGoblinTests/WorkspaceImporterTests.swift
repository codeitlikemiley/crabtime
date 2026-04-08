import XCTest
@testable import RustGoblin

final class WorkspaceImporterTests: XCTestCase {
    func testImportSingleChallengeDirectory() throws {
        let importer = WorkspaceImporter()
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge")

        let workspace = try importer.loadWorkspace(from: fixtureURL)

        XCTAssertEqual(workspace.exercises.count, 1)
        XCTAssertEqual(workspace.exercises.first?.title, "Sample Challenge")
        XCTAssertTrue(workspace.fileTree.contains { $0.name == "challenge.rs" })
        XCTAssertEqual(
            workspace.exercises.first?.sourceCode,
            """
            fn main() {
                let a = 1;
                let b = 2;
                println!("Sum: {}", a + b);
            }

            """
        )
    }

    func testImportSingleRustFile() throws {
        let importer = WorkspaceImporter()
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge/challenge.rs")

        let workspace = try importer.loadWorkspace(from: fixtureURL)

        XCTAssertEqual(workspace.exercises.count, 1)
        XCTAssertEqual(workspace.exercises.first?.sourceURL.lastPathComponent, "challenge.rs")
        XCTAssertTrue(workspace.fileTree.contains { $0.name == "challenge.rs" })
    }

    func testImportRustlingsStyleRepositoryDiscoversExerciseFilesInsteadOfRootCargoProject() throws {
        let importer = WorkspaceImporter()
        let fixtureURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/rustlings_like")

        let workspace = try importer.loadWorkspace(from: fixtureURL)

        XCTAssertEqual(workspace.exercises.count, 2)
        XCTAssertEqual(workspace.exercises.map(\.title), ["Variables One", "Variables Two"])
        XCTAssertEqual(workspace.exercises.map(\.difficulty), [.easy, .medium])
        XCTAssertFalse(workspace.exercises.contains { $0.sourceURL.lastPathComponent == "main.rs" })
        XCTAssertTrue(workspace.fileTree.contains { $0.name == "exercises" })
        XCTAssertTrue(workspace.fileTree.contains { $0.name == "src" })
    }

    func testImportExercismStyleWorkspaceUsesHelpMarkdownAsHint() throws {
        let importer = WorkspaceImporter()
        let tempRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectoryURL = tempRootURL.appendingPathComponent("src", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try """
        # Hello World

        Solve the classic Exercism exercise.
        """
        .write(to: tempRootURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try """
        ## How to debug

        Run `cargo test`.
        """
        .write(to: tempRootURL.appendingPathComponent("HELP.md"), atomically: true, encoding: .utf8)
        try """
        pub fn hello() -> &'static str {
            "Hello, World!"
        }
        """
        .write(to: sourceDirectoryURL.appendingPathComponent("lib.rs"), atomically: true, encoding: .utf8)

        let workspace = try importer.loadWorkspace(from: tempRootURL)

        XCTAssertEqual(workspace.exercises.count, 1)
        XCTAssertEqual(workspace.exercises.first?.hintURL?.lastPathComponent, "HELP.md")
        XCTAssertTrue(workspace.exercises.first?.hintContent.contains("How to debug") == true)
    }

    func testImportWorkspaceFileTreeIgnoresBuildArtifactsLockfilesAndDotPaths() throws {
        let importer = WorkspaceImporter()
        let tempRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectoryURL = tempRootURL.appendingPathComponent("src", isDirectory: true)
        let targetDirectoryURL = tempRootURL.appendingPathComponent("target", isDirectory: true)
        let dotDirectoryURL = tempRootURL.appendingPathComponent(".git", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotDirectoryURL, withIntermediateDirectories: true)

        try """
        fn main() {
            println!("hello");
        }
        """
        .write(to: sourceDirectoryURL.appendingPathComponent("main.rs"), atomically: true, encoding: .utf8)
        try """
        [package]
        name = "temp-workspace"
        version = "0.1.0"
        """
        .write(to: tempRootURL.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try "lock".write(to: tempRootURL.appendingPathComponent("Cargo.lock"), atomically: true, encoding: .utf8)
        try "ignore".write(to: tempRootURL.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "artifact".write(to: targetDirectoryURL.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/main".write(to: dotDirectoryURL.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let workspace = try importer.loadWorkspace(from: tempRootURL)
        let rootNames = Set(workspace.fileTree.map(\.name))

        XCTAssertTrue(rootNames.contains("src"))
        XCTAssertTrue(rootNames.contains("Cargo.toml"))
        XCTAssertFalse(rootNames.contains("target"))
        XCTAssertFalse(rootNames.contains("Cargo.lock"))
        XCTAssertFalse(rootNames.contains(".git"))
        XCTAssertFalse(rootNames.contains(".gitignore"))
    }
}
