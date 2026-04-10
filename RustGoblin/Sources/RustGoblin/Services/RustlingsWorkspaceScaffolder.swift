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

    // MARK: - Phase 1: Instant Stub Creation (no AI, no waiting)

    /// Creates stub files immediately — returns in < 1ms.
    /// Call this first, reload workspace, then call `enrichChallengeInBackground`.
    func createChallengeStub(
        named rawName: String,
        in workspaceRootURL: URL
    ) throws -> ChallengeResult {
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

        try fallbackExerciseStub(title: title).write(to: exerciseURL, atomically: true, encoding: .utf8)
        try fallbackSolutionStub(title: title).write(to: solutionURL, atomically: true, encoding: .utf8)
        try appendInfoEntryIfNeeded(slug: normalizedSlug, title: title, to: infoTomlURL)

        return ChallengeResult(
            title: title,
            slug: normalizedSlug,
            exerciseURL: exerciseURL,
            solutionURL: solutionURL,
            devUpdateMessage: nil
        )
    }


    // MARK: - Phase 2: Background AI Enrichment (parallel, non-blocking)

    /// Fires AI enrichment for a single challenge in a background Task.
    func enrichChallengeInBackground(
        result: ChallengeResult,
        providerManager: AIProviderManager?,
        onLog: @escaping @Sendable @MainActor (String) -> Void,
        onComplete: @escaping @Sendable @MainActor (URL, URL, String) -> Void
    ) {
        guard let providerManager else {
            onComplete(result.exerciseURL, result.solutionURL, "ℹ️ No AI provider — stub is ready for `\(result.slug)`.")
            return
        }

        Task { @MainActor in
            let enrichStart = Date()

            // ── Exercise ──────────────────────────────────────────────
            let (exerciseContent, exerciseGenerated) = await generateExerciseContent(
                title: result.title,
                providerManager: providerManager,
                onLog: { msg in onLog(msg) }
            )
            if exerciseGenerated {
                try? exerciseContent.write(to: result.exerciseURL, atomically: true, encoding: .utf8)
            }

            // ── Solution ──────────────────────────────────────────────
            let (solutionContent, solutionGenerated) = await generateSolutionContent(
                title: result.title,
                exerciseContent: exerciseContent,
                providerManager: providerManager,
                onLog: { msg in onLog(msg) }
            )
            if solutionGenerated {
                try? solutionContent.write(to: result.solutionURL, atomically: true, encoding: .utf8)
            }

            let elapsed = Int(Date().timeIntervalSince(enrichStart))
            let emoji = exerciseGenerated ? "✨" : (solutionGenerated ? "📝" : "ℹ️")
            let exStatus = exerciseGenerated ? "✅" : "❌"
            let solStatus = solutionGenerated ? "✅" : "❌"
            let detail = "exercise \(exStatus) solution \(solStatus) (\(elapsed)s)"

            onComplete(result.exerciseURL, result.solutionURL, "\(emoji) `\(result.slug)`: \(detail)")
        }
    }



    // MARK: - Core Workspace Setup

    private func appendInfoEntryIfNeeded(slug: String, title: String, to infoTomlURL: URL) throws {
        let existing = (try? String(contentsOf: infoTomlURL, encoding: .utf8)) ?? ""
        guard !existing.contains("name = \"\(slug)\"") else { return }

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
        guard ToolingHealthService.resolveExecutable(named: "rustlings") != nil else { return nil }

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
        guard !fileManager.fileExists(atPath: url.path) else { return }
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
        guard shouldRepairInfoToml(existing) else { return }
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
        guard shouldRepairCargoToml(existing) else { return }
        try canonicalCargoToml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func repairOrWriteRustAnalyzerToml(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            try canonicalRustAnalyzerToml.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard shouldRepairRustAnalyzerToml(existing) else { return }
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
        guard let range = contents.range(of: "[[exercises]]") else { return "" }
        return contents[range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - AI Content Generation

    /// Returns (content, isAIGenerated).
    /// On any failure (including 90s timeout), returns the fallback stub with `isAIGenerated = false`.
    /// Always logs diagnostic info through `onLog` so failures are never silent.
    private func generateExerciseContent(
        title: String,
        providerManager: AIProviderManager?,
        onLog: @MainActor (String) -> Void
    ) async -> (content: String, isAIGenerated: Bool) {
        guard let providerManager else {
            onLog("ℹ️ Exercise `\(title)`: no AI provider configured.")
            return (fallbackExerciseStub(title: title), false)
        }

        do {
            let userMessage = "Generate a Rustlings exercise for the topic: \"\(title)\""
            let raw = try await generateWithTimeout(
                providerManager: providerManager,
                systemPrompt: exerciseSystemPrompt,
                userMessage: userMessage
            )
            let cleaned = Self.stripMarkdownFences(from: raw)
            let hasRust = Self.looksLikeRustCode(cleaned)

            if cleaned.isEmpty || !hasRust {
                let preview = String(raw.prefix(200)).replacingOccurrences(of: "\n", with: "\\n")
                onLog("⚠️ Exercise `\(title)`: AI returned \(raw.count) chars but failed validation (hasRust=\(hasRust), cleanedEmpty=\(cleaned.isEmpty)). Preview: \(preview)")
                return (fallbackExerciseStub(title: title), false)
            }
            return (cleaned, true)
        } catch is AITimeoutError {
            onLog("⏱ Exercise `\(title)`: timed out after 90s.")
            return (fallbackExerciseStub(title: title), false)
        } catch {
            onLog("⚠️ Exercise `\(title)`: AI error — \(error.localizedDescription)")
            return (fallbackExerciseStub(title: title), false)
        }
    }

    /// Returns (content, isAIGenerated).
    private func generateSolutionContent(
        title: String,
        exerciseContent: String,
        providerManager: AIProviderManager?,
        onLog: @MainActor (String) -> Void
    ) async -> (content: String, isAIGenerated: Bool) {
        guard let providerManager else {
            onLog("ℹ️ Solution `\(title)`: no AI provider configured.")
            return (fallbackSolutionStub(title: title), false)
        }

        do {
            let userMessage = """
            Generate the solution file for this Rustlings exercise:

            ```rust
            \(exerciseContent)
            ```
            """
            let raw = try await generateWithTimeout(
                providerManager: providerManager,
                systemPrompt: solutionSystemPrompt,
                userMessage: userMessage
            )
            let cleaned = Self.stripMarkdownFences(from: raw)
            let hasRust = Self.looksLikeRustCode(cleaned)

            if cleaned.isEmpty || !hasRust {
                let preview = String(raw.prefix(200)).replacingOccurrences(of: "\n", with: "\\n")
                onLog("⚠️ Solution `\(title)`: AI returned \(raw.count) chars but failed validation (hasRust=\(hasRust), cleanedEmpty=\(cleaned.isEmpty)). Preview: \(preview)")
                return (fallbackSolutionStub(title: title), false)
            }
            return (cleaned, true)
        } catch is AITimeoutError {
            onLog("⏱ Solution `\(title)`: timed out after 90s.")
            return (fallbackSolutionStub(title: title), false)
        } catch {
            onLog("⚠️ Solution `\(title)`: AI error — \(error.localizedDescription)")
            return (fallbackSolutionStub(title: title), false)
        }
    }

    // MARK: - Timeout-safe AI call

    private struct AITimeoutError: Error {}

    /// Calls `providerManager.generate` with a 90-second deadline.
    /// Creates a MainActor task for the AI call and a background timer that cancels it on expiry.
    private func generateWithTimeout(
        providerManager: AIProviderManager,
        systemPrompt: String,
        userMessage: String,
        timeoutSeconds: Double = 90
    ) async throws -> String {
        let aiTask = Task { @MainActor in
            try await providerManager.generate(
                systemPrompt: systemPrompt,
                userMessage: userMessage
            )
        }

        let timer = Task.detached {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            aiTask.cancel()
        }

        do {
            let result = try await aiTask.value
            timer.cancel()
            return result
        } catch is CancellationError {
            timer.cancel()
            throw AITimeoutError()
        } catch {
            timer.cancel()
            throw error
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
        - Mirror the EXACT same structure as the exercise file.
        - Replace all `todo!()` with the correct working implementation.
        - Replace `// TODO:` comments with brief explanatory comments.
        - The code MUST contain `fn main() {}`.
        - If the exercise has `#[cfg(test)] mod tests`, include the SAME tests (they must all pass).
        - The code MUST pass `clippy -D warnings` on Rust edition 2024.
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

    // MARK: - Markdown & Rust Validation

    static func stripMarkdownFences(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fencePattern = #"^```(?:rust|rs)?\s*\n([\s\S]*?)\n```\s*$"#
        if let regex = try? NSRegularExpression(pattern: fencePattern, options: []),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let captureRange = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let blockPattern = #"```(?:rust|rs)?\s*\n([\s\S]*?)\n```"#
        if let regex = try? NSRegularExpression(pattern: blockPattern, options: []),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let captureRange = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func looksLikeRustCode(_ text: String) -> Bool {
        let rustSignals = ["fn ", "struct ", "impl ", "enum ", "use ", "let ", "pub ", "mod ", "trait ", "type "]
        return rustSignals.contains(where: { text.contains($0) })
    }

    // MARK: - Canonical Templates

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
        process.environment = DependencyManager.shared.defaultEnvironment

        let stdoutTask = Task.detached { try stdoutPipe.fileHandleForReading.readToEnd() ?? Data() }
        let stderrTask = Task.detached { try stderrPipe.fileHandleForReading.readToEnd() ?? Data() }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                Task {
                    do {
                        let stdoutData = try await stdoutTask.value
                        let stderrData = try await stderrTask.value
                        continuation.resume(returning: ProcessOutput(
                            commandDescription: commandDescription,
                            stdout: String(decoding: stdoutData, as: UTF8.self),
                            stderr: String(decoding: stderrData, as: UTF8.self),
                            terminationStatus: terminatedProcess.terminationStatus
                        ))
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
            case .invalidName: "Enter a valid challenge name."
            }
        }
    }
}
