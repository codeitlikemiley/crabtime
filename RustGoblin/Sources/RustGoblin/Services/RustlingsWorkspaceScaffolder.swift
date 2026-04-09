import Foundation

@MainActor
struct RustlingsWorkspaceScaffolder {
    struct ChallengeResult: Sendable {
        let title: String
        let slug: String
        let exerciseURL: URL
        let solutionURL: URL
        let devUpdateMessage: String?
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createEmptyWorkspace(named rawName: String, at rootURL: URL) throws {
        try ensureWorkspaceShell(named: rawName, at: rootURL, repairExisting: false)
    }

    func createChallenge(
        named rawName: String,
        in workspaceRootURL: URL,
        providerManager: AIProviderManager? = nil
    ) async throws -> ChallengeResult {
        let requestedSlug = slug(from: rawName)
        guard !requestedSlug.isEmpty else {
            throw WorkspaceChallengeError.invalidName
        }

        try ensureWorkspaceShell(named: workspaceRootURL.lastPathComponent, at: workspaceRootURL, repairExisting: true)

        let exercisesURL = workspaceRootURL.appendingPathComponent("exercises", isDirectory: true)
        let solutionsURL = workspaceRootURL.appendingPathComponent("solutions", isDirectory: true)
        let infoTomlURL = workspaceRootURL.appendingPathComponent("info.toml", isDirectory: false)

        try fileManager.createDirectory(at: exercisesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: solutionsURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: infoTomlURL.path) {
            try canonicalInfoTomlHeader.write(to: infoTomlURL, atomically: true, encoding: .utf8)
        }

        let normalizedSlug = nextAvailableSlug(basedOn: requestedSlug, in: exercisesURL)
        let title = prettifiedTitle(from: normalizedSlug.replacingOccurrences(of: "_", with: " "))

        let exerciseURL = exercisesURL.appendingPathComponent("\(normalizedSlug).rs", isDirectory: false)
        let solutionURL = solutionsURL.appendingPathComponent("\(normalizedSlug).rs", isDirectory: false)

        // Step 1: Generate exercise file (AI or fallback stub)
        let exerciseContent = await generateExerciseContent(
            title: title,
            providerManager: providerManager
        )
        try exerciseContent.write(to: exerciseURL, atomically: true, encoding: .utf8)

        // Step 2: Generate solution file (AI or fallback stub) — uses exercise as context
        let solutionContent = await generateSolutionContent(
            title: title,
            exerciseContent: exerciseContent,
            providerManager: providerManager
        )
        try solutionContent.write(to: solutionURL, atomically: true, encoding: .utf8)

        try appendInfoEntryIfNeeded(slug: normalizedSlug, title: title, to: infoTomlURL)

        let devUpdateMessage = try await runRustlingsDevUpdateIfAvailable(in: workspaceRootURL)

        return ChallengeResult(
            title: title,
            slug: normalizedSlug,
            exerciseURL: exerciseURL,
            solutionURL: solutionURL,
            devUpdateMessage: devUpdateMessage
        )
    }

    private func appendInfoEntryIfNeeded(slug: String, title: String, to infoTomlURL: URL) throws {
        let existing = (try? String(contentsOf: infoTomlURL, encoding: .utf8)) ?? ""
        guard !existing.contains("name = \"\(slug)\"") else {
            return
        }

        let hintBody = [
            "Implement \(title).",
            "",
            "- Read the failing tests",
            "- Make the smallest working change first"
        ].joined(separator: "\n")

        let entry = [
            "",
            "[[exercises]]",
            "name = \"\(slug)\"",
            "path = \"exercises/\(slug).rs\"",
            "mode = \"test\"",
            "hint = \"\"\"",
            hintBody,
            "\"\"\"",
            ""
        ].joined(separator: "\n")

        let separator = existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n"
        try (existing + separator + entry).write(to: infoTomlURL, atomically: true, encoding: .utf8)
    }

    private func runRustlingsDevUpdateIfAvailable(in workspaceRootURL: URL) async throws -> String? {
        guard ToolingHealthService.resolveExecutable(named: "rustlings") != nil else {
            return nil
        }

        let update = try await runProcess(
            currentDirectoryURL: workspaceRootURL,
            arguments: ["rustlings", "dev", "update"],
            commandDescription: "rustlings dev update"
        )

        let check = try await runProcess(
            currentDirectoryURL: workspaceRootURL,
            arguments: ["rustlings", "dev", "check"],
            commandDescription: "rustlings dev check"
        )

        let messages = [update.combinedText, check.combinedText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }

    private func writeIfMissing(_ text: String, to url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            return
        }

        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func ensureWorkspaceShell(named rawName: String, at rootURL: URL, repairExisting: Bool) throws {
        let title = prettifiedTitle(from: rawName)
        let cargoTomlURL = rootURL.appendingPathComponent("Cargo.toml", isDirectory: false)
        let readmeURL = rootURL.appendingPathComponent("README.md", isDirectory: false)
        let infoTomlURL = rootURL.appendingPathComponent("info.toml", isDirectory: false)
        let rustAnalyzerURL = rootURL.appendingPathComponent("rust-analyzer.toml", isDirectory: false)

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("exercises", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("solutions", isDirectory: true), withIntermediateDirectories: true)

        if repairExisting {
            try repairOrWriteInfoToml(at: infoTomlURL)
            try repairOrWriteCargoToml(at: cargoTomlURL)
            try repairOrWriteRustAnalyzerToml(at: rustAnalyzerURL)
            try writeIfMissing(readme(title: title), to: readmeURL)
        } else {
            try writeIfMissing(canonicalCargoToml, to: cargoTomlURL)
            try writeIfMissing(readme(title: title), to: readmeURL)
            try writeIfMissing(canonicalInfoTomlHeader, to: infoTomlURL)
            try writeIfMissing(canonicalRustAnalyzerToml, to: rustAnalyzerURL)
        }
    }

    private func repairOrWriteInfoToml(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            try canonicalInfoTomlHeader.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard shouldRepairInfoToml(existing) else {
            return
        }

        let exerciseEntries = extractExerciseEntries(from: existing)
        let rebuilt = canonicalInfoTomlHeader + (exerciseEntries.isEmpty ? "" : "\n\n" + exerciseEntries)
        try rebuilt.write(to: url, atomically: true, encoding: .utf8)
    }

    private func repairOrWriteCargoToml(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            try canonicalCargoToml.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard shouldRepairCargoToml(existing) else {
            return
        }

        try canonicalCargoToml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func repairOrWriteRustAnalyzerToml(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            try canonicalRustAnalyzerToml.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard shouldRepairRustAnalyzerToml(existing) else {
            return
        }

        try canonicalRustAnalyzerToml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func shouldRepairInfoToml(_ existing: String) -> Bool {
        existing.contains("# RustGoblin challenge workspace") || !existing.contains("format_version =")
    }

    private func shouldRepairCargoToml(_ existing: String) -> Bool {
        existing.contains("version = \"0.1.0\"")
            || existing.contains("name = \"examples\"")
            || !existing.contains("# Don't edit the `bin` list manually!")
            || !existing.contains("edition = \"2024\"")
    }

    private func shouldRepairRustAnalyzerToml(_ existing: String) -> Bool {
        existing.contains("[cargo]") || !existing.contains("check.command = \"clippy\"")
    }

    private func extractExerciseEntries(from contents: String) -> String {
        guard let range = contents.range(of: "[[exercises]]") else {
            return ""
        }

        return contents[range.lowerBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextAvailableSlug(basedOn baseSlug: String, in exercisesURL: URL) -> String {
        var candidate = baseSlug
        var suffix = 1

        while fileManager.fileExists(atPath: exercisesURL.appendingPathComponent("\(candidate).rs", isDirectory: false).path) {
            candidate = "\(baseSlug)\(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func slug(from rawName: String) -> String {
        let normalized = rawName
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")

        return normalized.isEmpty ? "challenge" : normalized
    }

    private func prettifiedTitle(from rawName: String) -> String {
        rawName
            .split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "-" })
            .map { $0.capitalized }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AI-Powered Exercise Generation

    private func generateExerciseContent(
        title: String,
        providerManager: AIProviderManager?
    ) async -> String {
        guard let providerManager else {
            return fallbackExerciseStub(title: title)
        }

        do {
            let raw = try await providerManager.generate(
                systemPrompt: exerciseSystemPrompt,
                userMessage: "Generate a Rustlings exercise for the topic: \"\(title)\""
            )
            let cleaned = Self.stripMarkdownFences(from: raw)
            guard !cleaned.isEmpty else {
                return fallbackExerciseStub(title: title)
            }
            return cleaned
        } catch {
            return fallbackExerciseStub(title: title)
        }
    }

    private func generateSolutionContent(
        title: String,
        exerciseContent: String,
        providerManager: AIProviderManager?
    ) async -> String {
        guard let providerManager else {
            return fallbackSolutionStub(title: title)
        }

        do {
            let userMessage = """
            Generate the solution file for this Rustlings exercise:

            ```rust
            \(exerciseContent)
            ```
            """
            let raw = try await providerManager.generate(
                systemPrompt: solutionSystemPrompt,
                userMessage: userMessage
            )
            let cleaned = Self.stripMarkdownFences(from: raw)
            guard !cleaned.isEmpty else {
                return fallbackSolutionStub(title: title)
            }
            return cleaned
        } catch {
            return fallbackSolutionStub(title: title)
        }
    }

    // MARK: - Prompts

    private var exerciseSystemPrompt: String {
        """
        You are an expert Rust exercise author generating Rustlings-style exercises.

        OUTPUT RULES:
        - Output ONLY valid Rust source code. No markdown fences, no prose, no explanations.
        - The file MUST contain a `fn main() {}` function (body can be empty or contain optional experiments).
        - Use `todo!()` macros for parts the learner must implement.
        - Use `// TODO:` comments to guide what needs to be done.
        - Do NOT use `// I AM NOT DONE` or any non-standard markers.
        - Code must compile on Rust edition 2024.

        EXERCISE COMPLEXITY RULES:
        - For simple syntax/familiarity topics (e.g. print, variables, types, borrowing):
          NO test module needed. The exercise is "fix this code so it compiles."
        - For algorithmic/data structure problems (e.g. LRU cache, linked list, binary search):
          Include a `#[cfg(test)] mod tests { ... }` block with test cases.
        - The more complex the problem, the MORE test cases you should include.
        - Minimum 3 test cases for complex exercises, covering normal + edge cases.

        STRUCTURE:
        1. `use` imports (if needed)
        2. Public types/functions with `todo!()` bodies
        3. `fn main() { // You can optionally experiment here. }`
        4. `#[cfg(test)] mod tests { ... }` (for complex exercises only)
        """
    }

    private var solutionSystemPrompt: String {
        """
        You are generating the SOLUTION file for a Rustlings exercise.

        OUTPUT RULES:
        - Output ONLY valid Rust source code. No markdown fences, no prose, no explanations.
        - Mirror the EXACT same structure as the exercise file:
          same function signatures, same type definitions, same test module.
        - Replace all `todo!()` with the correct working implementation.
        - Replace `// TODO:` comments with brief explanatory comments.
        - The code MUST contain `fn main() {}`.
        - If the exercise has `#[cfg(test)] mod tests`, include the SAME tests (they must all pass).
        - The code MUST pass `clippy -D warnings` on Rust edition 2024.
        - Use idiomatic Rust patterns (entry API for HashMap, collapsed if-let chains, etc.).
        """
    }

    // MARK: - Fallback Stubs

    private func fallbackExerciseStub(title: String) -> String {
        let challengeTitle = title.isEmpty ? "Custom Challenge" : title
        return """
        // TODO: implement \(challengeTitle)

        fn main() {
            // You can optionally experiment here.
        }
        """
    }

    private func fallbackSolutionStub(title: String) -> String {
        let challengeTitle = title.isEmpty ? "Custom Challenge" : title
        return """
        // Solution for \(challengeTitle).

        fn main() {
            // You can optionally experiment here.
        }
        """
    }

    // MARK: - Markdown Fence Stripping

    static func stripMarkdownFences(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ```rust ... ``` or ``` ... ``` wrapper
        let fencePattern = #"^```(?:rust|rs)?\s*\n([\s\S]*?)\n```\s*$"#
        if let regex = try? NSRegularExpression(pattern: fencePattern, options: []),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let captureRange = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Also handle if there are multiple code blocks — take the first one
        let blockPattern = #"```(?:rust|rs)?\s*\n([\s\S]*?)\n```"#
        if let regex = try? NSRegularExpression(pattern: blockPattern, options: []),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let captureRange = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    // MARK: - Canonical Workspace Templates

    private var canonicalCargoToml: String {
        """
        # Don't edit the `bin` list manually! It is updated by `rustlings dev update`
        bin = []

        [package]
        name = "exercises"
        edition = "2024"
        # Don't publish the exercises on crates.io!
        publish = false

        [dependencies]
        """
    }

    private func readme(title: String) -> String {
        """
        # \(title)

        A RustGoblin workspace for authoring custom Rustlings-style exercises.
        """
    }

    private var canonicalInfoTomlHeader: String {
        """
        format_version = 1

        welcome_message = \"\"\"Welcome to these community Rustlings exercises.\"\"\"

        final_message = \"\"\"We hope that you found the exercises helpful :D\"\"\"
        """
    }

    private var canonicalRustAnalyzerToml: String {
        """
        check.command = "clippy"
        check.extraArgs = ["--profile", "test"]
        cargo.targetDir = true
        """
    }

    private func runProcess(
        currentDirectoryURL: URL,
        arguments: [String],
        commandDescription: String
    ) async throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
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

extension RustlingsWorkspaceScaffolder {
    enum WorkspaceChallengeError: LocalizedError {
        case invalidName

        var errorDescription: String? {
            switch self {
            case .invalidName:
                "Enter a valid challenge name."
            }
        }
    }
}
