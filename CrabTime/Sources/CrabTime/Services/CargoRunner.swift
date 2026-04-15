import Foundation

/// Module-level actor cache for `cargo runner --help` availability checks.
/// Keyed by project root path so each workspace is checked at most once per session.
private actor CargoRunnerAvailabilityCache {
    static let shared = CargoRunnerAvailabilityCache()
    private var cache: [String: Bool] = [:]

    func availability(for path: String) -> Bool? {
        cache[path]
    }

    func setAvailability(_ available: Bool, for path: String) {
        cache[path] = available
    }
}

struct CargoRunner: Sendable {
    typealias ProcessRunner = @Sendable (URL, [String], String, [String: String]) async throws -> ProcessOutput

    private let processRunner: ProcessRunner
    private let sourcePresentationBuilder = SourcePresentationBuilder()

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

    func runOverride(args: [String], in directoryURL: URL) async throws -> ProcessOutput {
        try await processRunner(
            directoryURL,
            ["cargo", "runner", "override"] + args,
            "cargo runner override \(args.joined(separator: " "))",
            runnerEnvironment(projectRootURL: directoryURL)
        )
    }

    func run(exercise: ExerciseDocument, cursorLine: Int? = nil) async throws -> ProcessOutput {
        let runnerRootURL = projectRootURL(for: exercise.sourceURL, fallbackDirectoryURL: exercise.directoryURL)
        let environment = runnerEnvironment(projectRootURL: runnerRootURL)

        // Always prefer cargo runner — it's the primary execution strategy.
        // The CLI is intelligent and handles context-aware execution.
        if try await isCargoRunnerAvailable(in: runnerRootURL, environment: environment) {
            return try await runCargoRunner(
                sourceURL: exercise.sourceURL,
                projectRootURL: runnerRootURL,
                cursorLine: cursorLine,
                environment: environment
            )
        }

        // Fallback: standalone script via rustc
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

    func check(projectRootURL: URL) async throws -> ProcessOutput {
        let environment = runnerEnvironment(projectRootURL: projectRootURL)

        let infoTomlURL = projectRootURL.appendingPathComponent("info.toml")
        if FileManager.default.fileExists(atPath: infoTomlURL.path),
           ToolingHealthService.resolveExecutable(named: "rustlings") != nil {
            return try await processRunner(
                projectRootURL,
                ["rustlings", "dev", "check"],
                "rustlings dev check",
                environment
            )
        }

        if isCargoProjectRoot(projectRootURL) {
            return try await processRunner(
                projectRootURL,
                ["cargo", "check", "--color", "never", "--message-format", "short"],
                "cargo check",
                environment
            )
        }

        return ProcessOutput(
            commandDescription: "no check available",
            stdout: "",
            stderr: "",
            terminationStatus: 0
        )
    }

    private func runCargoRunner(
        sourceURL: URL,
        projectRootURL: URL,
        cursorLine: Int? = nil,
        environment: [String: String]
    ) async throws -> ProcessOutput {
        let targetPath = runnerTargetPath(for: sourceURL, relativeTo: projectRootURL)
        let targetArg: String
        if let cursorLine, cursorLine > 0 {
            targetArg = "\(targetPath):\(cursorLine)"
        } else {
            targetArg = targetPath
        }

        return try await processRunner(
            projectRootURL,
            ["cargo", "runner", "run", "--", targetArg],
            "cargo runner run \(targetArg)",
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
        let key = directoryURL.standardizedFileURL.path
        // Check the session-level cache first — avoids spawning cargo runner --help on every run.
        if let cached = await CargoRunnerAvailabilityCache.shared.availability(for: key) {
            return cached
        }

        let result = try await processRunner(
            directoryURL,
            ["cargo", "runner", "--help"],
            "cargo runner --help",
            environment
        )

        let available = result.terminationStatus == 0
        await CargoRunnerAvailabilityCache.shared.setAvailability(available, for: key)
        return available
    }

    private func runnerEnvironment(projectRootURL: URL) -> [String: String] {
        var environment = DependencyManager.shared.defaultEnvironment
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

    private func mergedStream(_ lhs: String, _ rhs: String) -> String {
        [lhs, rhs]
            .filter { !$0.isEmpty }
            .joined(separator: lhs.isEmpty || rhs.isEmpty ? "" : "\n")
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
        try await UnifiedProcessRunner.run(
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            commandDescription: commandDescription
        )
    }
}
