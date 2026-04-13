import Foundation

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

    private func runRustlingsExerciseIfNeeded(
        exercise: ExerciseDocument,
        projectRootURL: URL,
        environment: [String: String]
    ) async throws -> ProcessOutput? {
        guard isRustlingsExercise(exercise.sourceURL, projectRootURL: projectRootURL) else {
            return nil
        }

        if let cliResult = try await runRustlingsCLIIfAvailable(
            exercise: exercise,
            projectRootURL: projectRootURL,
            environment: environment
        ) {
            return cliResult
        }

        let sourceCode = try String(contentsOf: exercise.sourceURL, encoding: .utf8)
        let sourcePresentation = sourcePresentationBuilder.build(from: sourceCode)
        let targetPath = runnerTargetPath(for: exercise.sourceURL, relativeTo: projectRootURL)

        if !sourcePresentation.hiddenChecks.isEmpty {
            return try await runRustlingsTests(
                harnessURL: exercise.sourceURL,
                displayTargetPath: targetPath,
                projectRootURL: projectRootURL,
                environment: environment,
                cleanupURLs: []
            )
        }

        guard
            let solutionURL = rustlingsMirroredSolutionURL(for: exercise.sourceURL, projectRootURL: projectRootURL),
            let solutionCode = try? String(contentsOf: solutionURL, encoding: .utf8)
        else {
            return try await runRustlingsScript(
                sourceURL: exercise.sourceURL,
                displayTargetPath: targetPath,
                projectRootURL: projectRootURL,
                environment: environment
            )
        }

        let solutionPresentation = sourcePresentationBuilder.build(from: solutionCode)
        guard !solutionPresentation.hiddenChecks.isEmpty else {
            return try await runRustlingsScript(
                sourceURL: exercise.sourceURL,
                displayTargetPath: targetPath,
                projectRootURL: projectRootURL,
                environment: environment
            )
        }

        let mergedSource = mergedRustlingsSource(
            sourcePresentation: sourcePresentation,
            solutionPresentation: solutionPresentation
        )
        let temporaryHarnessURL = try writeRustlingsHarness(
            mergedSource: mergedSource,
            nextTo: exercise.sourceURL
        )

        return try await runRustlingsTests(
            harnessURL: temporaryHarnessURL,
            displayTargetPath: targetPath,
            projectRootURL: projectRootURL,
            environment: environment,
            cleanupURLs: [temporaryHarnessURL]
        )
    }

    private func runRustlingsCLIIfAvailable(
        exercise: ExerciseDocument,
        projectRootURL: URL,
        environment: [String: String]
    ) async throws -> ProcessOutput? {
        // Only use this path if the project is a Cargo workspace (has Cargo.toml with [[bin]])
        let cargoTomlURL = projectRootURL.appendingPathComponent("Cargo.toml")
        guard FileManager.default.fileExists(atPath: cargoTomlURL.path) else {
            return nil
        }

        let slug = exercise.sourceURL.deletingPathExtension().lastPathComponent
        // Use `cargo test --bin <slug>` for non-interactive execution.
        // `rustlings run <slug>` is an interactive watch mode that never terminates.
        return try await processRunner(
            projectRootURL,
            ["cargo", "test", "--bin", slug, "--", "--color", "never"],
            "cargo test --bin \(slug)",
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
        var environment = DependencyManager.shared.defaultEnvironment
        environment["PROJECT_ROOT"] = projectRootURL.path
        return environment
    }

    private func runRustlingsTests(
        harnessURL: URL,
        displayTargetPath: String,
        projectRootURL: URL,
        environment: [String: String],
        cleanupURLs: [URL]
    ) async throws -> ProcessOutput {
        let binaryURL = harnessURL.deletingLastPathComponent()
            .appendingPathComponent(".rustgoblin-test-\(UUID().uuidString)")

        defer {
            cleanupURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            try? FileManager.default.removeItem(at: binaryURL)
        }

        let compileArguments =
            ["rustc", "--test"]
            + cargoEditionArguments(in: projectRootURL)
            + ["-o", binaryURL.path, "--", harnessURL.path]
        let compileDescription = "rustc --test \(displayTargetPath)"
        let compileResult = try await processRunner(
            projectRootURL,
            compileArguments,
            compileDescription,
            environment
        )

        guard compileResult.terminationStatus == 0 else {
            return compileResult
        }

        let runDescription = "\(displayTargetPath) tests"
        let runResult = try await processRunner(
            projectRootURL,
            [binaryURL.path, "--color", "never"],
            runDescription,
            environment
        )

        return ProcessOutput(
            commandDescription: "\(compileDescription) && \(runDescription)",
            stdout: mergedStream(compileResult.stdout, runResult.stdout),
            stderr: mergedStream(compileResult.stderr, runResult.stderr),
            terminationStatus: runResult.terminationStatus
        )
    }

    private func runRustlingsScript(
        sourceURL: URL,
        displayTargetPath: String,
        projectRootURL: URL,
        environment: [String: String]
    ) async throws -> ProcessOutput {
        let binaryURL = projectRootURL
            .appendingPathComponent(".rustgoblin-run-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: binaryURL)
        }

        let compileArguments =
            ["rustc"]
            + cargoEditionArguments(in: projectRootURL)
            + ["-o", binaryURL.path, "--", sourceURL.path]
        let compileDescription = "rustc \(displayTargetPath)"
        let compileResult = try await processRunner(
            projectRootURL,
            compileArguments,
            compileDescription,
            environment
        )

        guard compileResult.terminationStatus == 0 else {
            return compileResult
        }

        let runResult = try await processRunner(
            projectRootURL,
            [binaryURL.path],
            displayTargetPath,
            environment
        )

        return ProcessOutput(
            commandDescription: "\(compileDescription) && \(displayTargetPath)",
            stdout: mergedStream(compileResult.stdout, runResult.stdout),
            stderr: mergedStream(compileResult.stderr, runResult.stderr),
            terminationStatus: runResult.terminationStatus
        )
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

    private func isRustlingsExercise(_ sourceURL: URL, projectRootURL: URL) -> Bool {
        runnerTargetPath(for: sourceURL, relativeTo: projectRootURL)
            .split(separator: "/")
            .contains(where: { $0 == "exercises" })
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

    private func rustlingsMirroredSolutionURL(for sourceURL: URL, projectRootURL: URL) -> URL? {
        let targetPathComponents = runnerTargetPath(for: sourceURL, relativeTo: projectRootURL)
            .split(separator: "/")
            .map(String.init)
        guard targetPathComponents.first == "exercises" else {
            return nil
        }

        var solutionURL = projectRootURL
        for component in ["solutions"] + Array(targetPathComponents.dropFirst()) {
            solutionURL.appendPathComponent(component)
        }

        let standardizedURL = solutionURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            return nil
        }

        return standardizedURL
    }

    private func mergedRustlingsSource(
        sourcePresentation: SourcePresentation,
        solutionPresentation: SourcePresentation
    ) -> String {
        var merged = sourcePresentation.visibleSource
        if !merged.hasSuffix("\n") {
            merged += "\n"
        }
        if !merged.hasSuffix("\n\n") {
            merged += "\n"
        }

        // Extract the test module from the solution's visible source
        let solutionSource = solutionPresentation.visibleSource
        if let testRange = solutionSource.range(of: "#[cfg(test", options: .backwards) {
            let testBlock = String(solutionSource[testRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !testBlock.isEmpty {
                merged += testBlock
                if !merged.hasSuffix("\n") {
                    merged += "\n"
                }
            }
        }

        return merged
    }

    private func writeRustlingsHarness(mergedSource: String, nextTo sourceURL: URL) throws -> URL {
        let harnessURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".rustgoblin-\(UUID().uuidString).rs")
        try mergedSource.write(to: harnessURL, atomically: true, encoding: .utf8)
        return harnessURL
    }

    private func cargoEditionArguments(in projectRootURL: URL) -> [String] {
        let cargoTomlURL = projectRootURL.appendingPathComponent("Cargo.toml")
        guard
            let cargoToml = try? String(contentsOf: cargoTomlURL, encoding: .utf8),
            let match = cargoToml.firstMatch(of: /edition\s*=\s*"([^"]+)"/)
        else {
            return []
        }

        return ["--edition", String(match.output.1)]
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
