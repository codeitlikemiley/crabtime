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

    func createChallenge(named rawName: String, in workspaceRootURL: URL) async throws -> ChallengeResult {
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

        let templates = templatePair(for: normalizedSlug, title: title)
        try templates.exercise.write(to: exerciseURL, atomically: true, encoding: .utf8)
        try templates.solution.write(to: solutionURL, atomically: true, encoding: .utf8)
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

    private func templatePair(for slug: String, title: String) -> (exercise: String, solution: String) {
        if slug == "lru_cache" {
            return (lruExerciseTemplate, lruSolutionTemplate)
        }

        let challengeTitle = title.isEmpty ? "Custom Challenge" : title
        let exercise = """
        // TODO: implement \(challengeTitle)

        fn main() {
            // You can optionally experiment here.
        }
        """

        let solution = """
        // Solution for \(challengeTitle).

        fn main() {
            // You can optionally experiment here.
        }
        """

        return (exercise, solution)
    }

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

    private var lruExerciseTemplate: String {
        """
        pub struct LruCache {
            // TODO: choose your data structures
        }

        impl LruCache {
            pub fn new(capacity: usize) -> Self {
                let _ = capacity;
                todo!("create a cache with the given capacity")
            }

            pub fn get(&mut self, key: i32) -> Option<i32> {
                let _ = key;
                todo!("return value and mark as recently used")
            }

            pub fn put(&mut self, key: i32, value: i32) {
                let _ = (key, value);
                todo!("insert or update, evict LRU if over capacity")
            }
        }

        fn main() {
            // You can optionally experiment here.
        }

        #[cfg(test)]
        mod tests {
            use super::*;

            #[test]
            fn test_lru_basic() {
                let mut cache = LruCache::new(2);
                cache.put(1, 1);
                cache.put(2, 2);
                assert_eq!(cache.get(1), Some(1));
                cache.put(3, 3);
                assert_eq!(cache.get(2), None);
                assert_eq!(cache.get(3), Some(3));
                cache.put(4, 4);
                assert_eq!(cache.get(1), None);
                assert_eq!(cache.get(3), Some(3));
                assert_eq!(cache.get(4), Some(4));
            }
        }
        """
    }

    private var lruSolutionTemplate: String {
        """
        use std::collections::{HashMap, VecDeque};

        pub struct LruCache {
            capacity: usize,
            map: HashMap<i32, i32>,
            order: VecDeque<i32>,
        }

        impl LruCache {
            pub fn new(capacity: usize) -> Self {
                Self {
                    capacity,
                    map: HashMap::new(),
                    order: VecDeque::new(),
                }
            }

            pub fn get(&mut self, key: i32) -> Option<i32> {
                if let Some(&value) = self.map.get(&key) {
                    self.promote(key);
                    Some(value)
                } else {
                    None
                }
            }

            pub fn put(&mut self, key: i32, value: i32) {
                if self.map.contains_key(&key) {
                    self.map.insert(key, value);
                    self.promote(key);
                    return;
                }

                if self.map.len() == self.capacity {
                    if let Some(lru) = self.order.pop_front() {
                        self.map.remove(&lru);
                    }
                }

                self.map.insert(key, value);
                self.order.push_back(key);
            }

            fn promote(&mut self, key: i32) {
                if let Some(position) = self.order.iter().position(|candidate| *candidate == key) {
                    self.order.remove(position);
                }
                self.order.push_back(key);
            }
        }

        fn main() {
            // You can optionally experiment here.
        }

        #[cfg(test)]
        mod tests {
            use super::*;

            #[test]
            fn test_lru_basic() {
                let mut cache = LruCache::new(2);
                cache.put(1, 1);
                cache.put(2, 2);
                assert_eq!(cache.get(1), Some(1));
                cache.put(3, 3);
                assert_eq!(cache.get(2), None);
                assert_eq!(cache.get(3), Some(3));
                cache.put(4, 4);
                assert_eq!(cache.get(1), None);
                assert_eq!(cache.get(3), Some(3));
                assert_eq!(cache.get(4), Some(4));
            }
        }
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
