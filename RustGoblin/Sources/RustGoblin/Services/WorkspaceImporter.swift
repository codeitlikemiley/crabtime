import Foundation

struct WorkspaceImporter {
    private let fileManager = FileManager.default
    private let sourcePresentationBuilder = SourcePresentationBuilder()

    func loadWorkspace(from selectionURL: URL) throws -> ExerciseWorkspace {
        let rootURL = normalizedRootURL(for: selectionURL)

        let candidates: [ExerciseCandidate]
        if isRunnableRustSourceFile(selectionURL) {
            candidates = [
                ExerciseCandidate(
                    sourceURL: selectionURL.standardizedFileURL,
                    directoryURL: selectionURL.deletingLastPathComponent().standardizedFileURL
                )
            ]
        } else {
            candidates = try discoverExerciseCandidates(from: rootURL)
        }

        guard !candidates.isEmpty else {
            throw ImportError.noExercisesFound(selectionURL.path)
        }

        let loadedExercises = try candidates.enumerated().map { index, candidate in
            try loadExercise(candidate: candidate, rootURL: rootURL, fallbackIndex: index)
        }

        let exercises = loadedExercises
            .sorted { lhs, rhs in
                if lhs.exercise.sortOrder != rhs.exercise.sortOrder {
                    return (lhs.exercise.sortOrder ?? .max) < (rhs.exercise.sortOrder ?? .max)
                }

                return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
            }
            .map(\.exercise)

        return ExerciseWorkspace(
            rootURL: rootURL,
            title: rootURL.lastPathComponent,
            exercises: exercises,
            fileTree: try buildFileTree(at: rootURL)
        )
    }

    private func discoverExerciseCandidates(from rootURL: URL) throws -> [ExerciseCandidate] {
        let fileCandidates = try discoverExerciseSourceFiles(from: rootURL)
        let directoryCandidates = try discoverStandaloneExerciseDirectories(from: rootURL)

        let merged = (fileCandidates + directoryCandidates)
            .reduce(into: [String: ExerciseCandidate]()) { result, candidate in
                result[candidate.sourceURL.standardizedFileURL.path] = candidate
            }

        return merged.values.sorted {
            $0.sourceURL.path.localizedCaseInsensitiveCompare($1.sourceURL.path) == .orderedAscending
        }
    }

    private func discoverExerciseSourceFiles(from rootURL: URL) throws -> [ExerciseCandidate] {
        var candidates: [ExerciseCandidate] = []
        for url in try descendantURLs(at: rootURL) {
            guard isRegularFile(url) else {
                continue
            }

            guard isRunnableRustSourceFile(url), isExerciseCollectionFile(url, rootURL: rootURL) else {
                continue
            }

            candidates.append(
                ExerciseCandidate(
                    sourceURL: url.standardizedFileURL,
                    directoryURL: url.deletingLastPathComponent().standardizedFileURL
                )
            )
        }

        return candidates
    }

    private func discoverStandaloneExerciseDirectories(from rootURL: URL) throws -> [ExerciseCandidate] {
        var matches: [ExerciseCandidate] = []
        let hasCollectionDescendants = try containsExerciseCollectionDescendant(in: rootURL)

        if !hasCollectionDescendants, let rootCandidate = try standaloneCandidate(in: rootURL, rootURL: rootURL) {
            matches.append(rootCandidate)
        }

        for candidateURL in try descendantURLs(at: rootURL) {
            guard isDirectory(candidateURL) else {
                continue
            }

            if isExerciseCollectionDirectory(candidateURL, rootURL: rootURL) {
                continue
            }

            if let candidate = try standaloneCandidate(in: candidateURL, rootURL: rootURL) {
                matches.append(candidate)
            }
        }

        return matches
    }

    private func standaloneCandidate(in directoryURL: URL, rootURL: URL) throws -> ExerciseCandidate? {
        if directoryURL.lastPathComponent == "src" {
            return nil
        }

        let contents = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        let preferredPaths = [
            directoryURL.appendingPathComponent("challenge.rs"),
            directoryURL.appendingPathComponent("src/main.rs"),
            directoryURL.appendingPathComponent("src/lib.rs")
        ]

        for preferredURL in preferredPaths where fileManager.fileExists(atPath: preferredURL.path) {
            return ExerciseCandidate(
                sourceURL: preferredURL.standardizedFileURL,
                directoryURL: directoryURL.standardizedFileURL
            )
        }

        let supportedSources = contents
            .filter { $0.hasSuffix(".rs") && $0 != "solution.rs" && $0 != "mod.rs" }

        guard supportedSources.count == 1 else {
            return nil
        }

        let sourceURL = directoryURL.appendingPathComponent(supportedSources[0]).standardizedFileURL

        if isExerciseCollectionFile(sourceURL, rootURL: rootURL) {
            return nil
        }

        return ExerciseCandidate(
            sourceURL: sourceURL,
            directoryURL: directoryURL.standardizedFileURL
        )
    }

    private func loadExercise(
        candidate: ExerciseCandidate,
        rootURL: URL,
        fallbackIndex: Int
    ) throws -> LoadedExercise {
        let directoryContents = try fileManager.contentsOfDirectory(
            at: candidate.directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let readmeURL = directoryContents.first { $0.lastPathComponent == "README.md" }
        let hintURL = directoryContents.first { $0.lastPathComponent == "hint.md" }
            ?? directoryContents.first { $0.lastPathComponent == "HELP.md" }
        let solutionURL = directoryContents.first { $0.lastPathComponent == "solution.rs" }
        let metadata = loadMetadata(for: candidate.sourceURL, in: candidate.directoryURL)

        let readmeContent = readContents(of: readmeURL) ?? defaultReadme(for: candidate.sourceURL)
        let hintContent = readContents(of: hintURL) ?? "No hints added for this exercise yet."
        let sourceCode = readContents(of: candidate.sourceURL) ?? ""
        let presentation = sourcePresentationBuilder.build(from: sourceCode)
        let solutionCode = readContents(of: solutionURL)
        let title = metadata.title ?? title(from: readmeContent, sourceURL: candidate.sourceURL)
        let summary = metadata.summary ?? summary(from: readmeContent)
        let difficulty = metadata.difficulty ?? ExerciseDifficulty.inferred(from: [title, summary].joined(separator: " "), fallbackIndex: fallbackIndex)
        let checks = presentation.hiddenChecks.isEmpty
            ? [
                ExerciseCheck(
                    id: "manual-run",
                    title: "Manual Run",
                    detail: "Run the current exercise to validate output and hidden tests.",
                    symbolName: "play.rectangle"
                )
            ]
            : presentation.hiddenChecks

        let exercise = ExerciseDocument(
            id: candidate.sourceURL.standardizedFileURL,
            title: title,
            summary: summary,
            difficulty: difficulty,
            sortOrder: metadata.order,
            directoryURL: candidate.directoryURL.standardizedFileURL,
            sourceURL: candidate.sourceURL.standardizedFileURL,
            readmeURL: readmeURL,
            hintURL: hintURL,
            solutionURL: solutionURL,
            readmeContent: readmeContent,
            hintContent: hintContent,
            sourceCode: sourceCode,
            solutionCode: solutionCode,
            presentation: presentation,
            checks: checks,
            fileNames: directoryContents.map(\.lastPathComponent).sorted()
        )

        let relativePath = relativePath(from: candidate.sourceURL, rootURL: rootURL)
        return LoadedExercise(exercise: exercise, relativePath: relativePath)
    }

    private func buildFileTree(at directoryURL: URL) throws -> [WorkspaceFileNode] {
        let children = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        return try children
            .filter(shouldIncludeInFileTree(_:))
            .sorted(by: compareNodes)
            .map(buildNode(from:))
    }

    private func buildNode(from url: URL) throws -> WorkspaceFileNode {
        let isDirectory = isDirectory(url)

        let children: [WorkspaceFileNode]
        if isDirectory {
            children = try buildFileTree(at: url)
        } else {
            children = []
        }

        return WorkspaceFileNode(
            id: url,
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            children: children
        )
    }

    private func compareNodes(lhs: URL, rhs: URL) -> Bool {
        let lhsIsDirectory = isDirectory(lhs)
        let rhsIsDirectory = isDirectory(rhs)

        if lhsIsDirectory != rhsIsDirectory {
            return lhsIsDirectory && !rhsIsDirectory
        }

        return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
    }

    private func shouldIncludeInFileTree(_ url: URL) -> Bool {
        let name = url.lastPathComponent

        if name.hasPrefix(".") {
            return false
        }

        if name == "target" || name == "Cargo.lock" {
            return false
        }

        return true
    }

    private func loadMetadata(for sourceURL: URL, in directoryURL: URL) -> ExerciseMetadata {
        let candidateURLs = [
            directoryURL.appendingPathComponent("info.toml"),
            sourceURL.deletingPathExtension().appendingPathExtension("toml")
        ]

        for candidateURL in candidateURLs where fileManager.fileExists(atPath: candidateURL.path) {
            guard let contents = readContents(of: candidateURL) else {
                continue
            }

            return parseMetadataTOML(contents)
        }

        return ExerciseMetadata()
    }

    private func parseMetadataTOML(_ contents: String) -> ExerciseMetadata {
        var metadata = ExerciseMetadata()

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            guard !line.isEmpty, !line.hasPrefix("#"), let equalsIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch key {
            case "title", "name":
                metadata.title = value
            case "summary", "description", "brief":
                metadata.summary = value
            case "difficulty":
                metadata.difficulty = ExerciseDifficulty(rawValue: value.lowercased())
            case "order":
                metadata.order = Int(value)
            default:
                continue
            }
        }

        return metadata
    }

    private func readContents(of url: URL?) -> String? {
        guard let url else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func title(from markdown: String, sourceURL: URL) -> String {
        if let heading = markdown
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { $0.hasPrefix("# ") }) {
            return heading.replacingOccurrences(of: "# ", with: "")
        }

        return sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func summary(from markdown: String) -> String {
        markdown
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") })
            ?? "Interactive Rust exercise."
    }

    private func defaultReadme(for sourceURL: URL) -> String {
        """
        # \(sourceURL.deletingPathExtension().lastPathComponent.capitalized)

        This exercise was imported from `\(sourceURL.lastPathComponent)`.
        """
    }

    private func normalizedRootURL(for selectionURL: URL) -> URL {
        if isRunnableRustSourceFile(selectionURL) {
            return selectionURL.deletingLastPathComponent().standardizedFileURL
        }

        return selectionURL.standardizedFileURL
    }

    private func isRunnableRustSourceFile(_ url: URL) -> Bool {
        url.pathExtension == "rs" && url.lastPathComponent != "solution.rs" && url.lastPathComponent != "mod.rs"
    }

    private func isExerciseCollectionDirectory(_ url: URL, rootURL: URL) -> Bool {
        relativePathComponents(for: url, rootURL: rootURL).contains("exercises")
    }

    private func isExerciseCollectionFile(_ url: URL, rootURL: URL) -> Bool {
        relativePathComponents(for: url, rootURL: rootURL).contains("exercises")
    }

    private func relativePathComponents(for url: URL, rootURL: URL) -> [String] {
        let resolvedURLComponents = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let resolvedRootComponents = rootURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents

        guard resolvedURLComponents.starts(with: resolvedRootComponents) else {
            return resolvedURLComponents
        }

        return Array(resolvedURLComponents.dropFirst(resolvedRootComponents.count))
    }

    private func relativePath(from url: URL, rootURL: URL) -> String {
        relativePathComponents(for: url, rootURL: rootURL).joined(separator: "/")
    }

    private func containsExerciseCollectionDescendant(in rootURL: URL) throws -> Bool {
        for candidateURL in try descendantURLs(at: rootURL) {
            guard isDirectory(candidateURL) else {
                continue
            }

            if isExerciseCollectionDirectory(candidateURL, rootURL: rootURL) {
                return true
            }
        }

        return false
    }

    private func descendantURLs(at rootURL: URL) throws -> [URL] {
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var descendants: [URL] = []
        for childURL in children {
            descendants.append(childURL)

            if isDirectory(childURL) {
                descendants.append(contentsOf: try descendantURLs(at: childURL))
            }
        }

        return descendants
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

private extension WorkspaceImporter {
    struct ExerciseCandidate: Equatable {
        let sourceURL: URL
        let directoryURL: URL
    }

    struct ExerciseMetadata {
        var title: String?
        var summary: String?
        var difficulty: ExerciseDifficulty?
        var order: Int?
    }

    struct LoadedExercise {
        let exercise: ExerciseDocument
        let relativePath: String
    }
}

extension WorkspaceImporter {
    enum ImportError: LocalizedError {
        case noExercisesFound(String)

        var errorDescription: String? {
            switch self {
            case .noExercisesFound(let path):
                "No Rust exercises were found in \(path). Import a folder that contains runnable Rust files or a compatible exercise collection."
            }
        }
    }
}
