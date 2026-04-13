import Foundation

struct ExerciseContextBuilder {
    @MainActor
    func build(from store: WorkspaceStore, processStore: ProcessStore?) -> String {
        var sections: [String] = []

        if let workspace = store.workspace {
            let rootURL = workspace.rootURL.standardizedFileURL

            if let exercise = store.selectedExercise {
                sections.append(exerciseInstructions)
                sections.append("""
                Exercise title: \(exercise.title)
                Workspace: \(workspace.title)
                Source path: \(relativePath(for: exercise.sourceURL.standardizedFileURL, rootURL: rootURL))
                Summary: \(exercise.summary)
                """)

                if !exercise.readmeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append("README / instructions:\n\(exercise.readmeContent)")
                }

                if !exercise.hintContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append("Hints / HELP:\n\(exercise.hintContent)")
                }

                sections.append("Current source buffer (may include unsaved edits):\n```rust\n\(store.editorText)\n```")

                let siblingFiles = loadSiblingFiles(for: exercise, rootURL: rootURL)
                if !siblingFiles.isEmpty {
                    sections.append("Relevant exercise files (.rs, .md, Cargo.toml):\n" + siblingFiles.joined(separator: "\n\n"))
                }
            } else {
                sections.append("""
                You are helping a learner inside a Rust workspace in Crab Time.
                No exercise is currently selected, so use the workspace context below when it exists.
                Focus on explanation, debugging, and next steps.
                Do not pretend to see files or exercise instructions that are not included.
                """)

                sections.append("""
                Workspace: \(workspace.title)
                Root path: \(rootURL.path)
                Exercise count: \(workspace.exercises.count)
                """)

                if let activeDocumentURL = store.activeDocumentURL?.standardizedFileURL {
                    let language = fenceLanguage(for: activeDocumentURL)
                    let bufferText = store.isShowingReadonlyPreview
                        ? store.explorerPreviewText
                        : store.editorText
                    sections.append("""
                    Active document: \(relativePath(for: activeDocumentURL, rootURL: rootURL))
                    Current buffer (may include unsaved edits):
                    ```\(language)
                    \(bufferText)
                    ```
                    """)
                }

                let workspaceFiles = loadWorkspaceFiles(rootURL: rootURL)
                if !workspaceFiles.isEmpty {
                    sections.append("Relevant workspace files:\n" + workspaceFiles.joined(separator: "\n\n"))
                }
            }
        } else {
            sections.append("""
            You are helping a learner in Crab Time without an active workspace or exercise.
            Answer general Rust, debugging, tooling, or exercise-authoring questions.
            Be explicit when local project context is unavailable.
            """)
        }

        appendRuntimeSections(from: store, processStore: processStore, to: &sections)
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
            .compactMap { renderFileContents(at: $0, rootURL: rootURL) }
    }

    private func loadWorkspaceFiles(rootURL: URL) -> [String] {
        [
            rootURL.appendingPathComponent("Cargo.toml"),
            rootURL.appendingPathComponent("README.md")
        ]
        .filter { FileManager.default.fileExists(atPath: $0.path) }
        .compactMap { renderFileContents(at: $0, rootURL: rootURL) }
    }

    private func renderFileContents(at fileURL: URL, rootURL: URL) -> String? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        return "\(relativePath(for: fileURL, rootURL: rootURL))\n```\(fenceLanguage(for: fileURL))\n\(content)\n```"
    }

    @MainActor
    private func appendRuntimeSections(from store: WorkspaceStore, processStore: ProcessStore?, to sections: inout [String]) {
        if let processStore = processStore, !store.consoleOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Terminal Output:\n```text\n\(store.consoleOutput)\n```")
        }

        if let processStore = processStore, !processStore.diagnostics.isEmpty {
            let diagnosticsText = processStore.diagnostics.map { diagnostic in
                let lineSuffix = diagnostic.line.map { " @ line \($0)" } ?? ""
                return "[\(diagnostic.severity.rawValue.uppercased())] \(diagnostic.message)\(lineSuffix)"
            }.joined(separator: "\n")
            sections.append("Diagnostics:\n```text\n\(diagnosticsText)\n```")
        }
    }

    private func fenceLanguage(for fileURL: URL) -> String {
        let pathExtension = fileURL.pathExtension.lowercased()
        return pathExtension.isEmpty ? "text" : pathExtension
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private var exerciseInstructions: String {
        """
        You are helping a learner with a Rust exercise.
        Focus on explanation, debugging, and next steps.
        Do not rewrite the whole solution unless the user explicitly asks.
        Avoid spoilers from solution files.

        RUSTLINGS EXERCISE CONVENTIONS (follow these when generating or modifying exercises):
        - Every exercise AND solution file MUST contain a `fn main() {}` function (even if empty body).
          This is required because each file is compiled as a separate binary target.
        - Solution files mirror the exercise structure with the correct implementation filled in.
          They include the SAME test cases and function signatures as the exercise.
        - For simple syntax/familiarity exercises (e.g. fixing `printline!` to `println!`,
          adding `let` keyword), NO test cases are needed — the exercise simply needs to compile.
        - For more complex problems (data structures, algorithms, trait implementations),
          include meaningful test cases in a `#[cfg(test)] mod tests { ... }` block.
        - The more complex the problem, the MORE test cases should be included to validate correctness.
        - Exercise files use `todo!()` macros and `// TODO:` comments for parts the learner must complete.
        - Solution files replace `todo!()` with the working implementation and `// TODO:` with explanatory comments.
        """
    }
}
