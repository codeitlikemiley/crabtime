import XCTest
@testable import RustGoblin

final class CargoRunnerTests: XCTestCase {
    func testRunScript() async throws {
        let runner = CargoRunner()
        let sourceURL = URL(fileURLWithPath: "/Volumes/goldcoders/rustgoblin/tests/fixtures/sample_challenge/challenge.rs")

        let output = try await runner.runScript(at: sourceURL)

        XCTAssertEqual(output.terminationStatus, 0)
        XCTAssertTrue(output.stdout.contains("Sum: 3"))
    }

    func testRunExerciseInCargoProjectUsesCargoRunnerWithProjectRootEnvironment() async throws {
        let recorder = ProcessInvocationRecorder()
        let runner = CargoRunner { currentDirectoryURL, arguments, commandDescription, environment in
            await recorder.record(
                currentDirectoryURL: currentDirectoryURL,
                arguments: arguments,
                commandDescription: commandDescription,
                environment: environment
            )

            if arguments == ["cargo", "runner", "--help"] {
                return ProcessOutput(commandDescription: commandDescription, stdout: "", stderr: "", terminationStatus: 0)
            }

            return ProcessOutput(commandDescription: commandDescription, stdout: "ok", stderr: "", terminationStatus: 0)
        }

        let tempRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let testsDirectoryURL = tempRootURL.appendingPathComponent("tests", isDirectory: true)
        try FileManager.default.createDirectory(at: testsDirectoryURL, withIntermediateDirectories: true)
        try """
        [package]
        name = "hello-world"
        version = "0.1.0"
        edition = "2021"
        """
        .write(to: tempRootURL.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try "fn main() {}".write(to: testsDirectoryURL.appendingPathComponent("hello_world.rs"), atomically: true, encoding: .utf8)

        let exercise = ExerciseDocument(
            id: testsDirectoryURL.appendingPathComponent("hello_world.rs"),
            title: "Hello World",
            summary: "",
            difficulty: .easy,
            fileRole: .tests,
            sortOrder: nil,
            directoryURL: testsDirectoryURL,
            sourceURL: testsDirectoryURL.appendingPathComponent("hello_world.rs"),
            readmeURL: nil,
            hintURL: nil,
            solutionURL: nil,
            readmeContent: "",
            hintContent: "",
            sourceCode: "",
            solutionCode: nil,
            presentation: SourcePresentation(prefix: "", visibleSource: "", suffix: "", hiddenChecks: []),
            checks: [],
            fileNames: []
        )

        let output = try await runner.run(exercise: exercise)
        let invocations = await recorder.invocations

        XCTAssertEqual(output.terminationStatus, 0)
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].currentDirectoryURL, tempRootURL)
        XCTAssertEqual(invocations[0].arguments, ["cargo", "runner", "--help"])
        XCTAssertEqual(invocations[1].currentDirectoryURL, tempRootURL)
        XCTAssertEqual(invocations[1].arguments, ["cargo", "runner", "run", "tests/hello_world.rs"])
        XCTAssertEqual(invocations[1].environment["PROJECT_ROOT"], tempRootURL.path)
    }

    func testRunRustlingsExerciseUsesCargoRunner() async throws {
        let recorder = ProcessInvocationRecorder()
        let runner = CargoRunner { currentDirectoryURL, arguments, commandDescription, environment in
            await recorder.record(
                currentDirectoryURL: currentDirectoryURL,
                arguments: arguments,
                commandDescription: commandDescription,
                environment: environment
            )

            if arguments == ["cargo", "runner", "--help"] {
                return ProcessOutput(commandDescription: commandDescription, stdout: "", stderr: "", terminationStatus: 0)
            }

            return ProcessOutput(commandDescription: commandDescription, stdout: "test result: ok", stderr: "", terminationStatus: 0)
        }

        let tempRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let exerciseDirectoryURL = tempRootURL.appendingPathComponent("exercises/03_if", isDirectory: true)
        let solutionDirectoryURL = tempRootURL.appendingPathComponent("solutions/03_if", isDirectory: true)
        try FileManager.default.createDirectory(at: exerciseDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: solutionDirectoryURL, withIntermediateDirectories: true)
        try """
        [package]
        name = "rustlings-like"
        version = "0.1.0"
        edition = "2021"
        """
        .write(to: tempRootURL.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try """
        fn bigger(a: i32, b: i32) -> i32 {
            todo!()
        }
        """
        .write(to: exerciseDirectoryURL.appendingPathComponent("if3.rs"), atomically: true, encoding: .utf8)
        try """
        fn bigger(a: i32, b: i32) -> i32 {
            if a > b { a } else { b }
        }

        #[cfg(test)]
        mod tests {
            #[test]
            fn equal_numbers() {
                assert_eq!(42, bigger(42, 42));
            }
        }
        """
        .write(to: solutionDirectoryURL.appendingPathComponent("if3.rs"), atomically: true, encoding: .utf8)

        let exercise = ExerciseDocument(
            id: exerciseDirectoryURL.appendingPathComponent("if3.rs"),
            title: "If",
            summary: "",
            difficulty: .unknown,
            fileRole: .primary,
            sortOrder: nil,
            directoryURL: exerciseDirectoryURL,
            sourceURL: exerciseDirectoryURL.appendingPathComponent("if3.rs"),
            readmeURL: nil,
            hintURL: nil,
            solutionURL: solutionDirectoryURL.appendingPathComponent("if3.rs"),
            readmeContent: "",
            hintContent: "",
            sourceCode: "",
            solutionCode: nil,
            presentation: SourcePresentation(prefix: "", visibleSource: "", suffix: "", hiddenChecks: []),
            checks: [],
            fileNames: []
        )

        let output = try await runner.run(exercise: exercise)
        let invocations = await recorder.invocations

        XCTAssertEqual(output.terminationStatus, 0)
        // cargo runner --help + cargo runner run <path>
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].arguments, ["cargo", "runner", "--help"])
        XCTAssertEqual(invocations[1].arguments, ["cargo", "runner", "run", "exercises/03_if/if3.rs"])
        XCTAssertEqual(invocations[1].currentDirectoryURL, tempRootURL)
    }

    func testRunRustlingsExerciseWithoutTestsFallsToCargoRunner() async throws {
        let recorder = ProcessInvocationRecorder()
        let runner = CargoRunner { currentDirectoryURL, arguments, commandDescription, environment in
            await recorder.record(
                currentDirectoryURL: currentDirectoryURL,
                arguments: arguments,
                commandDescription: commandDescription,
                environment: environment
            )

            if arguments == ["cargo", "runner", "--help"] {
                return ProcessOutput(commandDescription: commandDescription, stdout: "", stderr: "", terminationStatus: 0)
            }

            return ProcessOutput(commandDescription: commandDescription, stdout: "Hello world!", stderr: "", terminationStatus: 0)
        }

        let tempRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let exerciseDirectoryURL = tempRootURL.appendingPathComponent("exercises/00_intro", isDirectory: true)
        try FileManager.default.createDirectory(at: exerciseDirectoryURL, withIntermediateDirectories: true)
        try """
        [package]
        name = "rustlings-like"
        version = "0.1.0"
        edition = "2021"
        """
        .write(to: tempRootURL.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try """
        fn main() {
            println!("Hello world!");
        }
        """
        .write(to: exerciseDirectoryURL.appendingPathComponent("intro2.rs"), atomically: true, encoding: .utf8)

        let exercise = ExerciseDocument(
            id: exerciseDirectoryURL.appendingPathComponent("intro2.rs"),
            title: "Intro",
            summary: "",
            difficulty: .unknown,
            fileRole: .primary,
            sortOrder: nil,
            directoryURL: exerciseDirectoryURL,
            sourceURL: exerciseDirectoryURL.appendingPathComponent("intro2.rs"),
            readmeURL: nil,
            hintURL: nil,
            solutionURL: nil,
            readmeContent: "",
            hintContent: "",
            sourceCode: "",
            solutionCode: nil,
            presentation: SourcePresentation(prefix: "", visibleSource: "", suffix: "", hiddenChecks: []),
            checks: [],
            fileNames: []
        )

        let output = try await runner.run(exercise: exercise)
        let invocations = await recorder.invocations

        XCTAssertEqual(output.terminationStatus, 0)
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].arguments, ["cargo", "runner", "--help"])
        XCTAssertEqual(invocations[1].arguments, ["cargo", "runner", "run", "exercises/00_intro/intro2.rs"])
    }
}

private actor ProcessInvocationRecorder {
    private(set) var invocations: [ProcessInvocation] = []

    func record(
        currentDirectoryURL: URL,
        arguments: [String],
        commandDescription: String,
        environment: [String: String]
    ) {
        invocations.append(
            ProcessInvocation(
                currentDirectoryURL: currentDirectoryURL,
                arguments: arguments,
                commandDescription: commandDescription,
                environment: environment
            )
        )
    }
}

private struct ProcessInvocation: Sendable {
    let currentDirectoryURL: URL
    let arguments: [String]
    let commandDescription: String
    let environment: [String: String]
}
