import Foundation
import XCTest
@testable import CrabTime

final class RepositoryClonerTests: XCTestCase {
    func testCloneLocalRepositoryReusesExistingDestination() async throws {
        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRepositoryURL = tempRootURL.appendingPathComponent("source-repo", isDirectory: true)
        let cloneLibraryURL = tempRootURL.appendingPathComponent("clones", isDirectory: true)

        try fileManager.createDirectory(at: sourceRepositoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cloneLibraryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        try "fn main() { println!(\"hello\"); }\n"
            .write(to: sourceRepositoryURL.appendingPathComponent("main.rs"), atomically: true, encoding: .utf8)

        try runGit(["init", "-b", "main"], in: sourceRepositoryURL)
        try runGit(["add", "."], in: sourceRepositoryURL)
        try runGit(
            [
                "-c", "user.name=CrabTime Tests",
                "-c", "user.email=tests@example.com",
                "commit", "-m", "Initial commit"
            ],
            in: sourceRepositoryURL
        )

        let cloner = RepositoryCloner(cloneLibraryURL: cloneLibraryURL)
        let repositoryURLString = sourceRepositoryURL.absoluteURL.absoluteString

        let firstCloneURL = try await cloner.clone(urlString: repositoryURLString)
        let secondCloneURL = try await cloner.clone(urlString: repositoryURLString)

        XCTAssertEqual(firstCloneURL, secondCloneURL)
        XCTAssertTrue(fileManager.fileExists(atPath: firstCloneURL.appendingPathComponent(".git").path))
    }

    private func runGit(_ arguments: [String], in workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = workingDirectory

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(stderr)")
            return
        }
    }
}
