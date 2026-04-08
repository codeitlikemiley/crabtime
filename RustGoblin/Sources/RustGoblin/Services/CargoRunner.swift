import Foundation

struct CargoRunner: Sendable {
    typealias ProcessRunner = @Sendable (URL, [String], String, [String: String]) async throws -> ProcessOutput

    private let processRunner: ProcessRunner

    init(processRunner: ProcessRunner? = nil) {
        self.processRunner = processRunner ?? { currentDirectoryURL, arguments, commandDescription, environment in
            try await Self.runProcess(
                currentDirectoryURL: currentDirectoryURL,
                arguments: arguments,
                commandDescription: commandDescription,
                environment: environment
            )
        }
    }

    func run(exercise: ExerciseDocument) async throws -> ProcessOutput {
        let runnerRootURL = projectRootURL(for: exercise.sourceURL, fallbackDirectoryURL: exercise.directoryURL)
        let environment = runnerEnvironment(projectRootURL: runnerRootURL)

        if try await isCargoRunnerAvailable(in: runnerRootURL, environment: environment) {
            let runnerResult = try await runCargoRunner(
                sourceURL: exercise.sourceURL,
                projectRootURL: runnerRootURL,
                environment: environment
            )

            if !looksLikeRunnerInvocationError(runnerResult) {
                return runnerResult
            }
        }

        if isCargoProjectRoot(runnerRootURL) {
            return try await runCargoProject(in: runnerRootURL, environment: environment)
        }

        return try await runScriptFallback(at: exercise.sourceURL, projectRootURL: runnerRootURL, environment: environment)
    }

    func runScript(at sourceURL: URL) async throws -> ProcessOutput {
        let runnerRootURL = projectRootURL(for: sourceURL, fallbackDirectoryURL: sourceURL.deletingLastPathComponent())
        let environment = runnerEnvironment(projectRootURL: runnerRootURL)

        if try await isCargoRunnerAvailable(in: runnerRootURL, environment: environment) {
            let runnerResult = try await runCargoRunner(
                sourceURL: sourceURL,
                projectRootURL: runnerRootURL,
                environment: environment
            )

            if !looksLikeRunnerInvocationError(runnerResult) {
                return runnerResult
            }
        }

        return try await runScriptFallback(at: sourceURL, projectRootURL: runnerRootURL, environment: environment)
    }

    private func runCargoRunner(
        sourceURL: URL,
        projectRootURL: URL,
        environment: [String: String]
    ) async throws -> ProcessOutput {
        let targetPath = runnerTargetPath(for: sourceURL, relativeTo: projectRootURL)

        return try await processRunner(
            projectRootURL,
            ["cargo", "runner", "run", targetPath],
            "cargo runner run \(targetPath)",
            environment
        )
    }

    private func runCargoProject(in directoryURL: URL, environment: [String: String]) async throws -> ProcessOutput {
        try await processRunner(
            directoryURL,
            ["cargo", "test", "--color", "never"],
            "cargo test",
            environment
        )
    }

    private func runScriptFallback(
        at sourceURL: URL,
        projectRootURL: URL,
        environment: [String: String]
    ) async throws -> ProcessOutput {
        try await processRunner(
            projectRootURL,
            ["cargo", "+nightly", "-Zscript", sourceURL.path],
            "cargo +nightly -Zscript \(sourceURL.lastPathComponent)",
            environment
        )
    }

    private func isCargoRunnerAvailable(in directoryURL: URL, environment: [String: String]) async throws -> Bool {
        let result = try await processRunner(
            directoryURL,
            ["cargo", "runner", "--help"],
            "cargo runner --help",
            environment
        )

        return result.terminationStatus == 0
    }

    private func runnerEnvironment(projectRootURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PROJECT_ROOT"] = projectRootURL.path
        return environment
    }

    private func projectRootURL(for sourceURL: URL, fallbackDirectoryURL: URL) -> URL {
        var candidateURL = sourceURL.deletingLastPathComponent().standardizedFileURL

        while true {
            if isCargoProjectRoot(candidateURL) {
                return candidateURL
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL == candidateURL {
                break
            }

            candidateURL = parentURL
        }

        return fallbackDirectoryURL.standardizedFileURL
    }

    private func isCargoProjectRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Cargo.toml").path)
    }

    private func runnerTargetPath(for sourceURL: URL, relativeTo rootURL: URL) -> String {
        let standardizedSourceURL = sourceURL.standardizedFileURL
        let standardizedRootURL = rootURL.standardizedFileURL
        let rootPath = standardizedRootURL.path
        let sourcePath = standardizedSourceURL.path

        if sourcePath == rootPath {
            return standardizedSourceURL.lastPathComponent
        }

        if sourcePath.hasPrefix(rootPath + "/") {
            return String(sourcePath.dropFirst(rootPath.count + 1))
        }

        return sourcePath
    }

    private func looksLikeRunnerInvocationError(_ result: ProcessOutput) -> Bool {
        let text = (result.stdout + "\n" + result.stderr).lowercased()
        return result.terminationStatus != 0 && (
            text.contains("usage: cargo runner") ||
            text.contains("unrecognized subcommand") ||
            text.contains("requires a subcommand") ||
            text.contains("unexpected argument")
        )
    }

    private static func runProcess(
        currentDirectoryURL: URL,
        arguments: [String],
        commandDescription: String,
        environment: [String: String]
    ) async throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task.detached {
            try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
        }
        let stderrTask = Task.detached {
            try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                Task {
                    do {
                        let stdoutData = try await stdoutTask.value
                        let stderrData = try await stderrTask.value

                        continuation.resume(
                            returning: ProcessOutput(
                                commandDescription: commandDescription,
                                stdout: String(decoding: stdoutData, as: UTF8.self),
                                stderr: String(decoding: stderrData, as: UTF8.self),
                                terminationStatus: terminatedProcess.terminationStatus
                            )
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                stdoutTask.cancel()
                stderrTask.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
