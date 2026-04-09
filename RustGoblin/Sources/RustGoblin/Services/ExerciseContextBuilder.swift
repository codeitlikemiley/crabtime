import Foundation

struct ExerciseContextBuilder {
    @MainActor
    func build(from store: WorkspaceStore) -> String {
        guard let workspace = store.workspace, let exercise = store.selectedExercise else {
            return "No exercise is currently selected."
        }

        let rootURL = workspace.rootURL.standardizedFileURL
        let sourceURL = exercise.sourceURL.standardizedFileURL
        let unsavedSource = store.editorText

        var sections: [String] = []
        sections.append("""
        You are helping a learner with a Rust exercise.
        Focus on explanation, debugging, and next steps.
        Do not rewrite the whole solution unless the user explicitly asks.
        Avoid spoilers from solution files.
        """)

        sections.append("""
        Exercise title: \(exercise.title)
        Workspace: \(workspace.title)
        Source path: \(relativePath(for: sourceURL, rootURL: rootURL))
        Summary: \(exercise.summary)
        """)

        if !exercise.readmeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("README / instructions:\n\(exercise.readmeContent)")
        }

        if !exercise.hintContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Hints / HELP:\n\(exercise.hintContent)")
        }

        sections.append("Current source buffer (may include unsaved edits):\n```rust\n\(unsavedSource)\n```")

        let siblingFiles = loadSiblingFiles(for: exercise, rootURL: rootURL)
        if !siblingFiles.isEmpty {
            sections.append("Relevant exercise files (.rs, .md, Cargo.toml):\n" + siblingFiles.joined(separator: "\n\n"))
        }

        if !store.consoleOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Latest run output:\n```text\n\(store.consoleOutput)\n```")
        }

        if !store.diagnostics.isEmpty {
            let diagnosticText = store.diagnostics.map { diagnostic in
                let lineSuffix = diagnostic.line.map { " @ line \($0)" } ?? ""
                return "[\(diagnostic.severity.rawValue.uppercased())] \(diagnostic.message)\(lineSuffix)"
            }.joined(separator: "\n")
            sections.append("Diagnostics:\n```text\n\(diagnosticText)\n```")
        }

        return sections.joined(separator: "\n\n")
    }

    private func loadSiblingFiles(for exercise: ExerciseDocument, rootURL: URL) -> [String] {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: exercise.directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return fileURLs
            .filter { $0.standardizedFileURL != exercise.sourceURL.standardizedFileURL }
            .filter { $0.lastPathComponent.lowercased() != "solution.rs" }
            .filter { ["rs", "md", "toml"].contains($0.pathExtension.lowercased()) || $0.lastPathComponent == "Cargo.toml" }
            .prefix(6)
            .compactMap { fileURL in
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    return nil
                }
                let language = fileURL.pathExtension.lowercased()
                return "\(relativePath(for: fileURL, rootURL: rootURL))\n```\(language)\n\(content)\n```"
            }
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
