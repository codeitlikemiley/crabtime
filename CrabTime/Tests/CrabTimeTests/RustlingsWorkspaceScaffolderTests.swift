import XCTest
@testable import CrabTime

final class RustlingsWorkspaceScaffolderTests: XCTestCase {
    @MainActor
    func testCreateEmptyWorkspaceSeedsEmptyExercisesArray() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let scaffolder = RustlingsWorkspaceScaffolder()
        try scaffolder.createEmptyWorkspace(named: "Cold Freeze", at: rootURL)

        let infoToml = try String(
            contentsOf: rootURL.appendingPathComponent("info.toml"),
            encoding: .utf8
        )

        XCTAssertTrue(infoToml.contains("format_version = 1"))
        XCTAssertTrue(infoToml.contains("exercises = []"))
    }

    @MainActor
    func testCreateChallengeStubMatchesRustlingsWorkspaceExpectations() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let scaffolder = RustlingsWorkspaceScaffolder()
        let result = try scaffolder.createChallengeStub(named: "Master Struct", in: rootURL)

        let infoToml = try String(
            contentsOf: rootURL.appendingPathComponent("info.toml"),
            encoding: .utf8
        )
        let cargoToml = try String(
            contentsOf: rootURL.appendingPathComponent("Cargo.toml"),
            encoding: .utf8
        )
        let exerciseStub = try String(contentsOf: result.exerciseURL, encoding: .utf8)
        let solutionStub = try String(contentsOf: result.solutionURL, encoding: .utf8)

        XCTAssertFalse(infoToml.contains("exercises = []"))
        XCTAssertTrue(infoToml.contains("[[exercises]]"))
        XCTAssertTrue(infoToml.contains("name = \"master_struct\""))
        XCTAssertTrue(infoToml.contains("test = false"))
        XCTAssertFalse(infoToml.contains("mode = \"test\""))

        XCTAssertTrue(cargoToml.contains("{ name = \"master_struct\", path = \"exercises/master_struct.rs\" }"))
        XCTAssertTrue(cargoToml.contains("{ name = \"master_struct_sol\", path = \"solutions/master_struct.rs\" }"))

        XCTAssertTrue(exerciseStub.contains("// TODO: implement Master Struct"))
        XCTAssertTrue(exerciseStub.contains("todo!()"))
        XCTAssertTrue(solutionStub.contains("fn build_message() -> &'static str"))
        XCTAssertFalse(solutionStub.contains("todo!()"))
    }

    private func makeTemporaryWorkspaceRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}
