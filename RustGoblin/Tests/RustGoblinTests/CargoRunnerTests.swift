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

        let rootURL = URL(fileURLWithPath: "/Users/uriah/Exercism/rust/hello-world")
        let exercise = ExerciseDocument(
            id: rootURL.appendingPathComponent("tests/hello_world.rs"),
            title: "Hello World",
            summary: "",
            difficulty: .easy,
            sortOrder: nil,
            directoryURL: rootURL.appendingPathComponent("tests", isDirectory: true),
            sourceURL: rootURL.appendingPathComponent("tests/hello_world.rs"),
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
        XCTAssertEqual(invocations[0].currentDirectoryURL, rootURL)
        XCTAssertEqual(invocations[0].arguments, ["cargo", "runner", "--help"])
        XCTAssertEqual(invocations[1].currentDirectoryURL, rootURL)
        XCTAssertEqual(invocations[1].arguments, ["cargo", "runner", "run", "tests/hello_world.rs"])
        XCTAssertEqual(invocations[1].environment["PROJECT_ROOT"], rootURL.path)
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
