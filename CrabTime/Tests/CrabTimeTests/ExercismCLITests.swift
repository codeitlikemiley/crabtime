import Foundation
import XCTest
@testable import CrabTime

final class ExercismCLITests: XCTestCase {
    func testStatusReadsConfiguredTokenAndWorkspace() throws {
        let tempRootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let homeURL = tempRootURL.appendingPathComponent("home", isDirectory: true)
        let workspaceURL = tempRootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try writeConfig(
            homeURL: homeURL,
            token: "token-123",
            workspace: workspaceURL.path
        )

        let cli = ExercismCLI(
            environment: [:],
            homeDirectoryURL: homeURL,
            executableResolver: { URL(fileURLWithPath: "/opt/homebrew/bin/exercism") },
            processRunner: { _, _, _ in
                ProcessOutput(commandDescription: "", stdout: "", stderr: "", terminationStatus: 0)
            }
        )

        let status = try cli.status()

        XCTAssertTrue(status.isInstalled)
        XCTAssertTrue(status.hasToken)
        XCTAssertEqual(status.workspaceURL, workspaceURL.standardizedFileURL)
        XCTAssertTrue(status.isConfigured)
    }

    func testDownloadParsesDestinationFromCLIOutput() async throws {
        let tempRootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let homeURL = tempRootURL.appendingPathComponent("home", isDirectory: true)
        let workspaceURL = tempRootURL.appendingPathComponent("workspace", isDirectory: true)
        let destinationURL = workspaceURL
            .appendingPathComponent("rust", isDirectory: true)
            .appendingPathComponent("hello-world", isDirectory: true)

        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try writeConfig(
            homeURL: homeURL,
            token: "token-123",
            workspace: workspaceURL.path
        )

        let cli = ExercismCLI(
            environment: [:],
            homeDirectoryURL: homeURL,
            executableResolver: { URL(fileURLWithPath: "/opt/homebrew/bin/exercism") },
            processRunner: { _, arguments, _ in
                XCTAssertEqual(arguments, ["download", "--track=rust", "--exercise=hello-world"])
                return ProcessOutput(
                    commandDescription: "exercism download",
                    stdout: "Downloaded to\n\(destinationURL.path)\n",
                    stderr: "",
                    terminationStatus: 0
                )
            }
        )

        let downloadedURL = try await cli.download(track: "rust", exercise: "hello-world")

        XCTAssertEqual(downloadedURL, destinationURL.standardizedFileURL)
    }

    func testDownloadReusesExistingDirectoryWhenExerciseAlreadyExists() async throws {
        let tempRootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let homeURL = tempRootURL.appendingPathComponent("home", isDirectory: true)
        let workspaceURL = tempRootURL.appendingPathComponent("workspace", isDirectory: true)
        let destinationURL = workspaceURL
            .appendingPathComponent("rust", isDirectory: true)
            .appendingPathComponent("hello-world", isDirectory: true)

        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try writeConfig(
            homeURL: homeURL,
            token: "token-123",
            workspace: workspaceURL.path
        )

        let cli = ExercismCLI(
            environment: [:],
            homeDirectoryURL: homeURL,
            executableResolver: { URL(fileURLWithPath: "/opt/homebrew/bin/exercism") },
            processRunner: { _, _, _ in
                ProcessOutput(
                    commandDescription: "exercism download",
                    stdout: "",
                    stderr: "Error: directory '\(destinationURL.path)' already exists, use --force to overwrite\n",
                    terminationStatus: 1
                )
            }
        )

        let downloadedURL = try await cli.download(track: "rust", exercise: "hello-world")

        XCTAssertEqual(downloadedURL, destinationURL.standardizedFileURL)
    }

    func testSubmitUsesExerciseDirectoryAndProvidedSolutionFiles() async throws {
        let tempRootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let homeURL = tempRootURL.appendingPathComponent("home", isDirectory: true)
        let workspaceURL = tempRootURL.appendingPathComponent("workspace", isDirectory: true)
        let exerciseURL = workspaceURL
            .appendingPathComponent("rust", isDirectory: true)
            .appendingPathComponent("hello-world", isDirectory: true)

        try FileManager.default.createDirectory(at: exerciseURL, withIntermediateDirectories: true)
        try writeConfig(
            homeURL: homeURL,
            token: "token-123",
            workspace: workspaceURL.path
        )

        let cli = ExercismCLI(
            environment: [:],
            homeDirectoryURL: homeURL,
            executableResolver: { URL(fileURLWithPath: "/opt/homebrew/bin/exercism") },
            processRunner: { _, arguments, currentDirectoryURL in
                XCTAssertEqual(arguments, ["submit", "src/lib.rs", "Cargo.toml"])
                XCTAssertEqual(currentDirectoryURL, exerciseURL)
                return ProcessOutput(
                    commandDescription: "exercism submit",
                    stdout: "Submitted",
                    stderr: "",
                    terminationStatus: 0
                )
            }
        )

        let result = try await cli.submit(
            exerciseDirectoryURL: exerciseURL,
            files: ["src/lib.rs", "Cargo.toml"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.stdout, "Submitted")
    }

    private func makeTemporaryRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func writeConfig(homeURL: URL, token: String, workspace: String) throws {
        let configDirectoryURL = homeURL
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("exercism", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        let data = """
        {
          "token": "\(token)",
          "workspace": "\(workspace)",
          "apibaseurl": "https://api.exercism.org/v1"
        }
        """.data(using: .utf8)!

        try data.write(to: configDirectoryURL.appendingPathComponent("user.json", isDirectory: false))
    }
}
