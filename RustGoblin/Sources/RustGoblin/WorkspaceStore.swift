import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class WorkspaceStore {
    var workspaceLibrary: [SavedWorkspaceRecord] = []
    var workspace: ExerciseWorkspace?
    var selectedWorkspaceRootPath: String?
    var selectedExerciseID: ExerciseDocument.ID?
    var selectedExplorerFileURL: URL?
    var openTabs: [ActiveDocumentTab] = []
    var editorText: String = ""
    var explorerPreviewText: String = ""
    var searchText: String = ""
    var selectedDifficultyFilter: ExerciseDifficulty?
    var completionFilter: ExerciseCompletionFilter = .open
    var isWorkspacePickerPresented: Bool = false
    var workspacePickerSearchText: String = ""
    var consoleOutput: String = "Import a folder or a Rust file to start building your exercise workspace.\n"
    var sessionLog: [String] = []
    var diagnostics: [Diagnostic] = []
    var selectedConsoleTab: ConsoleTab = .output
    var runState: RunState = .idle
    var lastCommandDescription: String = ""
    var lastTerminationStatus: Int32?
    var isInspectorVisible: Bool = true
    var isSolutionVisible: Bool = false
    var isEditorDirty: Bool = false
    var contentDisplayMode: ContentDisplayMode = .split
    var sidebarMode: SidebarMode = .exercises
    var isCloneSheetPresented: Bool = false
    var cloneRepositoryURL: String = ""
    var cloneErrorMessage: String?
    var isCloningRepository: Bool = false
    var isSubmittingExercism: Bool = false

    @ObservationIgnored private let importer: WorkspaceImporter
    @ObservationIgnored private let cargoRunner: CargoRunner
    @ObservationIgnored private let sourcePresentationBuilder: SourcePresentationBuilder
    @ObservationIgnored private let appPaths: AppStoragePaths
    @ObservationIgnored private let database: WorkspaceLibraryDatabase
    @ObservationIgnored private let repositoryCloner: RepositoryCloner
    @ObservationIgnored private let exercismCLI: ExercismCLI
    @ObservationIgnored private var isRestoringState = false
    @ObservationIgnored private var workspaceFileBaseline: [String: Data] = [:]

    init(
        appPaths: AppStoragePaths = .live(),
        importer: WorkspaceImporter = WorkspaceImporter(),
        cargoRunner: CargoRunner = CargoRunner(),
        sourcePresentationBuilder: SourcePresentationBuilder = SourcePresentationBuilder(),
        database: WorkspaceLibraryDatabase? = nil,
        repositoryCloner: RepositoryCloner? = nil,
        exercismCLI: ExercismCLI? = nil
    ) {
        self.appPaths = appPaths
        self.importer = importer
        self.cargoRunner = cargoRunner
        self.sourcePresentationBuilder = sourcePresentationBuilder
        var bootstrapMessages: [String] = []

        let resolvedDatabase: WorkspaceLibraryDatabase
        if let database {
            resolvedDatabase = database
        } else {
            do {
                resolvedDatabase = try WorkspaceLibraryDatabase(paths: appPaths)
            } catch {
                let fallbackPaths = AppStoragePaths.temporary(rootName: "RustGoblin-Fallback-\(UUID().uuidString)")
                resolvedDatabase = try! WorkspaceLibraryDatabase(paths: fallbackPaths)
                bootstrapMessages.append("Database fallback enabled: \(error.localizedDescription)")
            }
        }

        self.database = resolvedDatabase
        self.repositoryCloner = repositoryCloner ?? RepositoryCloner(cloneLibraryURL: appPaths.cloneLibraryURL)
        self.exercismCLI = exercismCLI ?? ExercismCLI()
        self.sessionLog = bootstrapMessages

        restorePersistedLibrary()
    }

    var hasSelection: Bool {
        selectedExercise != nil
    }

    var isRunning: Bool {
        runState == .running
    }

    var showsProblemPane: Bool {
        contentDisplayMode != .editorMaximized
    }

    var showsEditorPane: Bool {
        contentDisplayMode != .problemMaximized
    }

    var showsInspector: Bool {
        showsEditorPane && isInspectorVisible
    }

    var currentFileTree: [WorkspaceFileNode] {
        workspace?.fileTree ?? []
    }

    var currentOpenTabs: [ActiveDocumentTab] {
        openTabs
    }

    var currentOpenFiles: [URL] {
        openTabs.map(\.url)
    }

    var isShowingExplorerPreview: Bool {
        selectedExplorerFileURL != nil
    }

    var isShowingReadonlyPreview: Bool {
        guard let selectedExplorerFileURL else {
            return false
        }

        return selectedExplorerFileURL != selectedExercise?.sourceURL
    }

    var isShowingMarkdownPreview: Bool {
        guard isShowingReadonlyPreview else {
            return false
        }

        return selectedExplorerFileURL?.pathExtension.lowercased() == "md"
    }

    var currentWorkspaceRecord: SavedWorkspaceRecord? {
        guard let selectedWorkspaceRootPath else {
            return workspaceLibrary.first
        }

        return workspaceLibrary.first { $0.rootPath == selectedWorkspaceRootPath }
    }

    var filteredWorkspaceLibrary: [SavedWorkspaceRecord] {
        let trimmedQuery = workspacePickerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return workspaceLibrary
        }

        return workspaceLibrary.filter { record in
            [
                record.title,
                record.rootURL.lastPathComponent,
                record.cloneURL ?? ""
            ].contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }
    }

    var availableDifficultyFilters: [ExerciseDifficulty] {
        let difficulties = Set((workspace?.exercises ?? []).map(\.difficulty))
        return ExerciseDifficulty.allCases.filter { difficulty in
            guard difficulties.contains(difficulty) else {
                return false
            }

            if !supportsRustlingsDifficultyFilters && (difficulty == .core || difficulty == .kata) {
                return false
            }

            return difficulty != .unknown
        } + (difficulties.contains(.unknown) ? [.unknown] : [])
    }

    var showsDifficultyFilters: Bool {
        !availableDifficultyFilters.isEmpty
    }

    var hasSolutionPreview: Bool {
        guard let solution = selectedExercise?.solutionCode?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        return !solution.isEmpty
    }

    var activeEditorTitle: String {
        if let selectedExplorerFileURL, selectedExplorerFileURL != selectedExercise?.sourceURL {
            return selectedExplorerFileURL.lastPathComponent
        }

        return selectedExercise?.title ?? "Ready to Code"
    }

    var activeEditorSubtitle: String {
        if let selectedExplorerFileURL, let workspace {
            let relativePath = selectedExplorerFileURL.path.replacingOccurrences(of: workspace.rootURL.path + "/", with: "")
            return relativePath
        }

        return selectedExercise?.sourceURL.lastPathComponent ?? "Import an exercise to begin editing."
    }

    var activeEditorLineCount: Int {
        let source = isShowingReadonlyPreview ? explorerPreviewText : editorText
        return source.isEmpty ? 0 : source.split(whereSeparator: \.isNewline).count
    }

    var diagnosticsCount: Int {
        diagnostics.count
    }

    var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }

    var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }

    var visibleExercises: [ExerciseDocument] {
        guard let workspace else {
            return []
        }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return workspace.exercises.filter { exercise in
            let matchesDifficulty = selectedDifficultyFilter == nil || exercise.difficulty == selectedDifficultyFilter
            let isCompleted = isExerciseCompleted(exercise)
            let matchesCompletion: Bool
            switch completionFilter {
            case .open:
                matchesCompletion = !isCompleted
            case .done:
                matchesCompletion = isCompleted
            }
            let matchesQuery = trimmedQuery.isEmpty || [
                exercise.title,
                exercise.summary,
                exercise.sourceURL.lastPathComponent,
                currentWorkspaceRecord?.title ?? ""
            ].contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) })

            return matchesDifficulty && matchesCompletion && matchesQuery
        }
    }

    var selectedExercise: ExerciseDocument? {
        guard let workspace else {
            return nil
        }

        guard let selectedExerciseID else {
            return workspace.exercises.first
        }

        return workspace.exercises.first { $0.id == selectedExerciseID }
    }

    var currentProblemMarkdown: String {
        selectedExercise?.readmeContent ?? """
        # RustGoblin

        Import a Rust workspace or a challenge folder to start learning.
        """
    }

    var currentHintMarkdown: String {
        selectedExercise?.hintContent ?? "Hints show up here once an exercise is loaded."
    }

    var currentSolutionMarkdown: String? {
        guard isSolutionVisible, hasSolutionPreview else {
            return nil
        }

        return selectedExercise?.solutionCode
    }

    var currentChecks: [ExerciseCheck] {
        selectedExercise?.checks ?? []
    }

    var currentFiles: [String] {
        selectedExercise?.fileNames ?? []
    }

    var isExercismWorkspace: Bool {
        currentWorkspaceRecord?.sourceKind == .exercism
    }

    var canSubmitSelectedExerciseToExercism: Bool {
        isExercismWorkspace
            && hasSelection
            && runState == .succeeded
            && !isRunning
            && !isSubmittingExercism
            && (!modifiedWorkspaceRelativePaths.isEmpty || isEditorDirty)
    }

    private var supportsRustlingsDifficultyFilters: Bool {
        let candidates = [
            workspace?.title,
            currentWorkspaceRecord?.title,
            selectedWorkspaceRootPath
        ]

        return candidates
            .compactMap { $0 }
            .contains(where: { $0.localizedCaseInsensitiveContains("rustlings") })
    }

    var modifiedWorkspaceRelativePaths: [String] {
        guard let workspace else {
            return []
        }

        let rootURL = workspace.rootURL.standardizedFileURL

        return workspaceFileURLs(in: workspace.fileTree)
            .compactMap { fileURL in
                let standardizedURL = fileURL.standardizedFileURL
                let path = standardizedURL.path
                let currentData = try? Data(contentsOf: standardizedURL)
                let baselineData = workspaceFileBaseline[path]

                if baselineData == nil, currentData != nil {
                    return relativePath(for: standardizedURL, rootURL: rootURL)
                }

                guard let baselineData, let currentData, currentData != baselineData else {
                    return nil
                }

                return relativePath(for: standardizedURL, rootURL: rootURL)
            }
            .sorted()
    }

    func openWorkspace() {
        activateApplication()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Import Rust Exercises"
        panel.message = "Pick a folder that contains exercises, or select a Rust source file directly."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        importWorkspace(from: url, sourceKind: .imported, cloneURL: nil)
    }

    func showCloneSheet() {
        cloneErrorMessage = nil
        activateApplication()

        let alert = NSAlert()
        alert.messageText = "Clone Repository"
        alert.informativeText = "Paste a Git repository URL. RustGoblin will clone it into the local workspace library and load it."
        alert.addButton(withTitle: "Clone")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        inputField.placeholderString = "https://github.com/rust-lang/rustlings.git"
        inputField.stringValue = cloneRepositoryURL
        inputField.isEditable = true
        inputField.isSelectable = true
        alert.accessoryView = inputField
        let alertWindow = alert.window
        alertWindow.initialFirstResponder = inputField
        alertWindow.makeFirstResponder(inputField)
        inputField.currentEditor()?.selectAll(nil)
        alertWindow.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        cloneRepositoryURL = inputField.stringValue
        cloneRepository()
    }

    func showExercismStatus() {
        activateApplication()

        do {
            let status = try exercismCLI.status()
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Exercism CLI Setup"
            alert.informativeText = exercismStatusMessage(for: status)
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            showBlockingAlert(
                title: "Exercism CLI Setup",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    func showExercismDownloadPrompt() {
        activateApplication()

        let alert = NSAlert()
        alert.messageText = "Download Exercism Exercise"
        alert.informativeText = "Paste an Exercism download command or fill in the track and exercise below. RustGoblin will use your existing Exercism CLI setup and import the downloaded exercise."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let commandField = PromptTextField(frame: NSRect(x: 0, y: 0, width: 440, height: 30))
        commandField.placeholderString = "exercism download --track=rust --exercise=hello-world"
        commandField.font = .systemFont(ofSize: 13)
        commandField.bezelStyle = .roundedBezel
        commandField.isEditable = true
        commandField.isSelectable = true

        let trackField = PromptTextField(frame: NSRect(x: 0, y: 0, width: 440, height: 30))
        trackField.placeholderString = "rust"
        trackField.stringValue = "rust"
        trackField.font = .systemFont(ofSize: 13)
        trackField.bezelStyle = .roundedBezel
        trackField.isEditable = true
        trackField.isSelectable = true

        let exerciseField = PromptTextField(frame: NSRect(x: 0, y: 0, width: 440, height: 30))
        exerciseField.placeholderString = "hello-world"
        exerciseField.font = .systemFont(ofSize: 13)
        exerciseField.bezelStyle = .roundedBezel
        exerciseField.isEditable = true
        exerciseField.isSelectable = true

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 182))
        let commandLabel = promptLabel(title: "Command")
        commandLabel.frame = NSRect(x: 0, y: 158, width: 440, height: 16)
        commandField.frame = NSRect(x: 0, y: 126, width: 440, height: 30)

        let helperLabel = NSTextField(wrappingLabelWithString: "Paste `exercism download --track=rust --exercise=hello-world` or use the fields below.")
        helperLabel.font = .systemFont(ofSize: 11)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.frame = NSRect(x: 0, y: 94, width: 440, height: 28)

        let trackLabel = promptLabel(title: "Track")
        trackLabel.frame = NSRect(x: 0, y: 72, width: 440, height: 16)
        trackField.frame = NSRect(x: 0, y: 42, width: 440, height: 30)

        let exerciseLabel = promptLabel(title: "Exercise")
        exerciseLabel.frame = NSRect(x: 0, y: 20, width: 440, height: 16)
        exerciseField.frame = NSRect(x: 0, y: 0, width: 440, height: 30)

        accessoryView.addSubview(commandLabel)
        accessoryView.addSubview(commandField)
        accessoryView.addSubview(helperLabel)
        accessoryView.addSubview(trackLabel)
        accessoryView.addSubview(trackField)
        accessoryView.addSubview(exerciseLabel)
        accessoryView.addSubview(exerciseField)
        alert.accessoryView = accessoryView

        let alertWindow = alert.window
        alertWindow.initialFirstResponder = commandField
        DispatchQueue.main.async {
            alertWindow.makeFirstResponder(commandField)
            commandField.selectText(nil)
        }
        alertWindow.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            let input = try resolveExercismDownloadInput(
                command: commandField.stringValue,
                track: trackField.stringValue,
                exercise: exerciseField.stringValue
            )

            downloadExercismExercise(
                track: input.track,
                exercise: input.exercise
            )
        } catch {
            showBlockingAlert(
                title: "Download Exercism Exercise",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    func cloneRepository() {
        guard !cloneRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cloneErrorMessage = "Enter a repository URL."
            return
        }

        let requestedURL = cloneRepositoryURL
        isCloningRepository = true
        cloneErrorMessage = nil
        appendSessionMessage("Cloning repository \(requestedURL)")

        Task {
            do {
                let destinationURL = try await repositoryCloner.clone(urlString: requestedURL)
                appendSessionMessage("Cloned repository into \(destinationURL.lastPathComponent)")
                importWorkspace(from: destinationURL, sourceKind: .cloned, cloneURL: requestedURL)
                cloneRepositoryURL = ""
                isCloneSheetPresented = false
            } catch {
                cloneErrorMessage = error.localizedDescription
                consoleOutput += "Clone failed: \(error.localizedDescription)\n"
                appendSessionMessage("Clone failed for \(requestedURL)")
            }

            isCloningRepository = false
        }
    }

    func downloadExercismExercise(track: String, exercise: String) {
        let requestedTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedExercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !requestedTrack.isEmpty, !requestedExercise.isEmpty else {
            showBlockingAlert(
                title: "Download Exercism Exercise",
                message: "Enter both a track and an exercise slug.",
                style: .warning
            )
            return
        }

        appendSessionMessage("Downloading Exercism exercise \(requestedTrack)/\(requestedExercise)")

        Task {
            do {
                let destinationURL = try await exercismCLI.download(track: requestedTrack, exercise: requestedExercise)
                appendSessionMessage("Downloaded Exercism exercise into \(destinationURL.path)")
                importWorkspace(from: destinationURL, sourceKind: .exercism, cloneURL: nil)
            } catch {
                consoleOutput += "Exercism download failed: \(error.localizedDescription)\n"
                appendSessionMessage("Exercism download failed for \(requestedTrack)/\(requestedExercise)")
                showBlockingAlert(
                    title: "Download Exercism Exercise",
                    message: error.localizedDescription,
                    style: .warning
                )
            }
        }
    }

    func importWorkspace(from url: URL, sourceKind: WorkspaceSourceKind = .imported, cloneURL: String? = nil) {
        if isEditorDirty {
            saveSelectedExercise()
        }
        loadWorkspace(at: url, sourceKind: sourceKind, cloneURL: cloneURL, restoreState: true)
    }

    func loadPersistedWorkspace(rootPath: String) {
        guard let record = workspaceLibrary.first(where: { $0.rootPath == rootPath }), !record.isMissing else {
            return
        }

        if isEditorDirty {
            saveSelectedExercise()
        }

        loadWorkspace(at: record.rootURL, sourceKind: record.sourceKind, cloneURL: record.cloneURL, restoreState: true)
        isWorkspacePickerPresented = false
    }

    func selectExercise(id: ExerciseDocument.ID?) {
        guard let id, selectedExerciseID != id else {
            return
        }

        if hasSelection, !isRestoringState {
            saveSelectedExercise()
        }

        applySelection(for: id)
        persistCurrentWorkspaceSnapshot()
    }

    func activateTab(_ tab: ActiveDocumentTab) {
        activateDocument(at: tab.url, persistState: true)
    }

    func activateOpenFile(_ url: URL) {
        activateDocument(at: url, persistState: true)
    }

    func openExplorerFile(_ url: URL) {
        registerOpenTab(url)
        activateDocument(at: url, persistState: true)
    }

    func saveSelectedExercise() {
        guard
            var workspace,
            let selectedExerciseID,
            let selectedIndex = workspace.exercises.firstIndex(where: { $0.id == selectedExerciseID })
        else {
            return
        }

        let selectedExercise = workspace.exercises[selectedIndex]

        do {
            let rebuiltSource = selectedExercise.presentation.rebuild(with: editorText)
            try rebuiltSource.write(to: selectedExercise.sourceURL, atomically: true, encoding: .utf8)
            let updatedPresentation = sourcePresentationBuilder.build(from: rebuiltSource)
            let existingChecks = workspace.exercises[selectedIndex].checks
            workspace.exercises[selectedIndex].sourceCode = rebuiltSource
            workspace.exercises[selectedIndex].presentation = updatedPresentation
            workspace.exercises[selectedIndex].checks = mergeCheckStatuses(
                existing: existingChecks,
                replacement: updatedPresentation.hiddenChecks
            )
            self.workspace = workspace
            isEditorDirty = false
            appendSessionMessage("Saved \(selectedExercise.sourceURL.lastPathComponent)")
            persistCurrentWorkspaceSnapshot()
        } catch {
            consoleOutput += "Save failed: \(error.localizedDescription)\n"
            appendSessionMessage("Save failed for \(selectedExercise.sourceURL.lastPathComponent)")
        }
    }

    func runSelectedExercise() {
        guard selectedExercise != nil else {
            return
        }

        saveSelectedExercise()

        Task {
            await performRun()
        }
    }

    func submitSelectedExerciseToExercism() {
        guard let selectedExercise, canSubmitSelectedExerciseToExercism else {
            return
        }

        saveSelectedExercise()
        let modifiedFiles = modifiedWorkspaceRelativePaths

        guard !modifiedFiles.isEmpty else {
            consoleOutput += "Exercism submit skipped: no modified files to submit.\n"
            appendSessionMessage("Skipped Exercism submit for \(selectedExercise.title)")
            return
        }

        Task {
            await performExercismSubmit(for: selectedExercise, files: modifiedFiles)
        }
    }

    func toggleProblemPaneVisibility() {
        contentDisplayMode = contentDisplayMode == .editorMaximized ? .split : .editorMaximized
        persistCurrentWorkspaceSnapshot()
    }

    func toggleInspector() {
        isInspectorVisible.toggle()
    }

    func selectSidebarMode(_ mode: SidebarMode) {
        guard sidebarMode != mode else {
            return
        }

        sidebarMode = mode
        persistCurrentWorkspaceSnapshot()
    }

    func selectDifficultyFilter(_ filter: ExerciseDifficulty?) {
        guard filter == nil || availableDifficultyFilters.contains(filter!) else {
            selectedDifficultyFilter = nil
            persistCurrentWorkspaceSnapshot()
            return
        }

        selectedDifficultyFilter = filter
        persistCurrentWorkspaceSnapshot()
    }

    func selectCompletionFilter(_ filter: ExerciseCompletionFilter) {
        guard completionFilter != filter else {
            return
        }

        completionFilter = filter
        persistCurrentWorkspaceSnapshot()
    }

    func persistSearchTextChange() {
        persistCurrentWorkspaceSnapshot()
    }

    func toggleSolutionVisibility() {
        isSolutionVisible.toggle()
    }

    func handleEditorTextChange() {
        isEditorDirty = editorText != selectedExercise?.presentation.visibleSource
    }

    func resetSelectedExercise() {
        guard let selectedExercise else {
            return
        }

        editorText = selectedExercise.presentation.visibleSource
        isEditorDirty = false
        appendSessionMessage("Reset \(selectedExercise.sourceURL.lastPathComponent) to last loaded state")
    }

    func toggleProblemMaximize() {
        contentDisplayMode = contentDisplayMode == .problemMaximized ? .split : .problemMaximized
    }

    func toggleEditorMaximize() {
        contentDisplayMode = contentDisplayMode == .editorMaximized ? .split : .editorMaximized
    }

    private func restorePersistedLibrary() {
        do {
            let fetchedRecords = try database.fetchWorkspaces()
            workspaceLibrary = try fetchedRecords.map { record in
                var updated = record
                updated.isMissing = !FileManager.default.fileExists(atPath: record.rootPath)
                try database.upsertWorkspace(updated)
                return updated
            }

            if let mostRecentAvailableWorkspace = workspaceLibrary.first(where: { !$0.isMissing }) {
                loadWorkspace(
                    at: mostRecentAvailableWorkspace.rootURL,
                    sourceKind: mostRecentAvailableWorkspace.sourceKind,
                    cloneURL: mostRecentAvailableWorkspace.cloneURL,
                    restoreState: true
                )
            }
        } catch {
            sessionLog.insert("Failed to restore persisted library: \(error.localizedDescription)", at: 0)
        }
    }

    private func loadWorkspace(
        at url: URL,
        sourceKind: WorkspaceSourceKind,
        cloneURL: String?,
        restoreState: Bool
    ) {
        do {
            var loadedWorkspace = try importer.loadWorkspace(from: url)
            let rootPath = loadedWorkspace.rootURL.standardizedFileURL.path
            let progressLookup = try database.fetchProgress(for: rootPath)
            applyStoredProgress(progressLookup, to: &loadedWorkspace)

            workspace = loadedWorkspace
            workspaceFileBaseline = snapshotWorkspaceFiles(for: loadedWorkspace)
            selectedWorkspaceRootPath = rootPath
            diagnostics = []
            selectedConsoleTab = .output
            runState = .idle
            lastCommandDescription = ""
            lastTerminationStatus = nil
            isSolutionVisible = false
            contentDisplayMode = .split
            consoleOutput = "Imported \(loadedWorkspace.exercises.count) exercise(s) from \(loadedWorkspace.rootURL.lastPathComponent).\n"
            appendSessionMessage("Workspace loaded from \(loadedWorkspace.rootURL.path)")

            let existingRecord = try database.fetchWorkspace(rootPath: rootPath)
            let record = SavedWorkspaceRecord(
                rootPath: rootPath,
                title: loadedWorkspace.title,
                sourceKind: sourceKind,
                cloneURL: cloneURL ?? existingRecord?.cloneURL,
                addedAt: existingRecord?.addedAt ?? Date(),
                lastOpenedAt: Date(),
                isMissing: false
            )
            try database.upsertWorkspace(record)
            refreshWorkspaceLibrary(with: record)

            if restoreState, let savedState = try database.fetchWorkspaceState(for: rootPath) {
                applySavedState(savedState, in: loadedWorkspace)
            } else if let firstExercise = loadedWorkspace.exercises.first {
                applySelection(for: firstExercise.id)
                openTabs = [ActiveDocumentTab(url: firstExercise.sourceURL)]
            } else {
                clearActiveDocumentState()
            }

            persistCurrentWorkspaceSnapshot()
        } catch {
            workspace = nil
            workspaceFileBaseline = [:]
            selectedWorkspaceRootPath = nil
            selectedExerciseID = nil
            clearActiveDocumentState()
            isEditorDirty = false
            consoleOutput = "Import failed: \(error.localizedDescription)\n"
            appendSessionMessage("Import failed for \(url.path)")
        }
    }

    private func applySavedState(_ state: WorkspaceSessionState, in workspace: ExerciseWorkspace) {
        isRestoringState = true
        defer { isRestoringState = false }

        searchText = state.searchQuery
        selectedDifficultyFilter = state.difficultyFilter
        completionFilter = state.completionFilter
        sidebarMode = state.sidebarMode
        if let savedDifficulty = state.difficultyFilter,
           !availableDifficultyFilters.contains(savedDifficulty) {
            selectedDifficultyFilter = nil
        }

        let resolvedExercise = workspace.exercises.first {
            $0.sourceURL.standardizedFileURL.path == state.selectedExercisePath
        } ?? workspace.exercises.first

        if let resolvedExercise {
            applySelection(for: resolvedExercise.id)
        }

        let resolvedTabs = state.openTabs.filter { FileManager.default.fileExists(atPath: $0.path) }
        openTabs = resolvedTabs.isEmpty
            ? resolvedExercise.map { [ActiveDocumentTab(url: $0.sourceURL)] } ?? []
            : resolvedTabs

        if let activeTabPath = state.activeTabPath,
           let activeTab = openTabs.first(where: { $0.path == activeTabPath }) {
            activateDocument(at: activeTab.url, persistState: false)
        } else if let resolvedExercise {
            activateDocument(at: resolvedExercise.sourceURL, persistState: false)
        } else {
            clearActiveDocumentState()
        }
    }

    private func applySelection(for exerciseID: ExerciseDocument.ID) {
        selectedExerciseID = exerciseID
        editorText = selectedExercise?.presentation.visibleSource ?? ""
        explorerPreviewText = ""
        isEditorDirty = false
        isSolutionVisible = false

        if let sourceURL = selectedExercise?.sourceURL {
            selectedExplorerFileURL = sourceURL
            registerOpenTab(sourceURL)
        }
    }

    private func activateDocument(at url: URL, persistState: Bool) {
        guard let workspace else {
            return
        }

        selectedExplorerFileURL = url.standardizedFileURL
        registerOpenTab(url)

        if let matchingExercise = workspace.exercises.first(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            selectedExerciseID = matchingExercise.id
            editorText = matchingExercise.presentation.visibleSource
            isEditorDirty = false
        } else {
            explorerPreviewText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        if persistState {
            persistCurrentWorkspaceSnapshot()
        }
    }

    private func registerOpenTab(_ url: URL) {
        let tab = ActiveDocumentTab(url: url)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
    }

    private func clearActiveDocumentState() {
        selectedExplorerFileURL = nil
        explorerPreviewText = ""
        openTabs = []
        editorText = ""
    }

    private func applyStoredProgress(_ progressLookup: [String: StoredExerciseProgress], to workspace: inout ExerciseWorkspace) {
        workspace.exercises = workspace.exercises.map { exercise in
            guard let progress = progressLookup[exercise.sourceURL.standardizedFileURL.path] else {
                return exercise
            }

            var exercise = exercise
            exercise.checks = exercise.checks.map { check in
                var check = check
                if let storedStatus = progress.checkStatuses[check.id] {
                    check.status = storedStatus
                }
                return check
            }
            return exercise
        }
    }

    private func refreshWorkspaceLibrary(with record: SavedWorkspaceRecord) {
        workspaceLibrary.removeAll { $0.rootPath == record.rootPath }
        workspaceLibrary.insert(record, at: 0)
        workspaceLibrary.sort { lhs, rhs in
            if lhs.lastOpenedAt != rhs.lastOpenedAt {
                return lhs.lastOpenedAt > rhs.lastOpenedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func persistCurrentWorkspaceSnapshot() {
        guard let workspace, let selectedWorkspaceRootPath else {
            return
        }

        do {
            if var record = workspaceLibrary.first(where: { $0.rootPath == selectedWorkspaceRootPath }) {
                record.title = workspace.title
                record.lastOpenedAt = Date()
                record.isMissing = false
                try database.upsertWorkspace(record)
                refreshWorkspaceLibrary(with: record)
            }

            let workspaceState = WorkspaceSessionState(
                workspaceRootPath: selectedWorkspaceRootPath,
                selectedExercisePath: selectedExercise?.sourceURL.standardizedFileURL.path,
                activeTabPath: selectedExplorerFileURL?.standardizedFileURL.path,
                openTabs: openTabs,
                sidebarMode: sidebarMode,
                searchQuery: searchText,
                difficultyFilter: selectedDifficultyFilter,
                completionFilter: completionFilter
            )
            try database.saveWorkspaceState(workspaceState)

            let progressEntries = workspace.exercises.map { exercise in
                StoredExerciseProgress(
                    workspaceRootPath: selectedWorkspaceRootPath,
                    exercisePath: exercise.sourceURL.standardizedFileURL.path,
                    difficulty: exercise.difficulty,
                    passedCheckCount: exercise.checks.filter { $0.status == .passed }.count,
                    totalCheckCount: exercise.checks.count,
                    lastRunStatus: inferredRunState(for: exercise),
                    lastOpenedAt: Date(),
                    checkStatuses: Dictionary(uniqueKeysWithValues: exercise.checks.map { ($0.id, $0.status) })
                )
            }
            try database.saveProgress(progressEntries, for: selectedWorkspaceRootPath)
        } catch {
            sessionLog.insert("Persistence failed: \(error.localizedDescription)", at: 0)
        }
    }

    private func inferredRunState(for exercise: ExerciseDocument) -> RunState {
        if exercise.checks.contains(where: { $0.status == .failed }) {
            return .failed
        }

        if exercise.checks.contains(where: { $0.status == .passed }) {
            return .succeeded
        }

        return .idle
    }

    private func isExerciseCompleted(_ exercise: ExerciseDocument) -> Bool {
        !exercise.checks.isEmpty && exercise.checks.allSatisfy { $0.status == .passed }
    }

    private func performRun() async {
        guard let selectedExercise else {
            return
        }

        runState = .running
        selectedConsoleTab = .output
        lastCommandDescription = ""
        consoleOutput += "\n[\(Date().formatted(date: .omitted, time: .standard))] Running \(selectedExercise.title)…\n"
        appendSessionMessage("Started \(selectedExercise.title)")

        do {
            let result = try await cargoRunner.run(exercise: selectedExercise)
            lastCommandDescription = result.commandDescription
            lastTerminationStatus = result.terminationStatus
            diagnostics = DiagnosticParser.parse(result.stderr)
            applyCheckResults(from: result)

            if !result.stdout.isEmpty {
                consoleOutput += result.stdout
            }

            if !result.stderr.isEmpty {
                consoleOutput += result.stderr
            }

            runState = result.terminationStatus == 0 ? .succeeded : .failed

            appendSessionMessage(
                "Finished \(selectedExercise.title) with status \(result.terminationStatus)"
            )
            persistCurrentWorkspaceSnapshot()
        } catch {
            runState = .failed
            consoleOutput += "Run failed: \(error.localizedDescription)\n"
            appendSessionMessage("Run failed for \(selectedExercise.title)")
            persistCurrentWorkspaceSnapshot()
        }
    }

    private func performExercismSubmit(for exercise: ExerciseDocument, files: [String]) async {
        guard isExercismWorkspace, let workspace else {
            return
        }

        isSubmittingExercism = true
        selectedConsoleTab = .output
        consoleOutput += "\n[\(Date().formatted(date: .omitted, time: .standard))] Submitting \(exercise.title) to Exercism…\n"
        appendSessionMessage("Submitting \(exercise.title) to Exercism")

        defer {
            isSubmittingExercism = false
        }

        do {
            let result = try await exercismCLI.submit(
                exerciseDirectoryURL: workspace.rootURL,
                files: files
            )
            lastCommandDescription = result.commandDescription
            lastTerminationStatus = result.terminationStatus

            if !result.stdout.isEmpty {
                consoleOutput += result.stdout
                if !result.stdout.hasSuffix("\n") {
                    consoleOutput += "\n"
                }
            }

            if !result.stderr.isEmpty {
                consoleOutput += result.stderr
                if !result.stderr.hasSuffix("\n") {
                    consoleOutput += "\n"
                }
            }

            appendSessionMessage("Submitted \(exercise.title) to Exercism")
            workspaceFileBaseline = snapshotWorkspaceFiles(for: workspace)
        } catch {
            consoleOutput += "Exercism submit failed: \(error.localizedDescription)\n"
            appendSessionMessage("Exercism submit failed for \(exercise.title)")
        }
    }

    private func applyCheckResults(from result: ProcessOutput) {
        guard
            var workspace,
            let selectedExerciseID,
            let selectedIndex = workspace.exercises.firstIndex(where: { $0.id == selectedExerciseID })
        else {
            return
        }

        let existingChecks = workspace.exercises[selectedIndex].checks
        let combinedOutput = [result.stdout, result.stderr].joined(separator: "\n").lowercased()

        workspace.exercises[selectedIndex].checks = existingChecks.map { check in
            var check = check

            if check.id == "manual-run" {
                check.status = result.terminationStatus == 0 ? .passed : .failed
                return check
            }

            let token = check.id.lowercased()

            if combinedOutput.contains("\(token) ... ok") || combinedOutput.contains("\(token) ... passed") {
                check.status = .passed
            } else if combinedOutput.contains("\(token) ... failed") || combinedOutput.contains(token + " failed") {
                check.status = .failed
            } else {
                check.status = result.terminationStatus == 0 ? .passed : .failed
            }

            return check
        }

        self.workspace = workspace
    }

    private func mergeCheckStatuses(existing: [ExerciseCheck], replacement: [ExerciseCheck]) -> [ExerciseCheck] {
        guard !replacement.isEmpty else {
            return existing.isEmpty
                ? [
                    ExerciseCheck(
                        id: "manual-run",
                        title: "Manual Run",
                        detail: "Run the current exercise to validate output and hidden tests.",
                        symbolName: "play.rectangle"
                    )
                ]
                : existing
        }

        var statusLookup: [String: CheckStatus] = [:]
        for check in existing {
            statusLookup[check.id] = check.status
        }

        return replacement.map { check in
            var check = check
            check.status = statusLookup[check.id] ?? .idle
            return check
        }
    }

    private func activateApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func snapshotWorkspaceFiles(for workspace: ExerciseWorkspace) -> [String: Data] {
        Dictionary(
            uniqueKeysWithValues: workspaceFileURLs(in: workspace.fileTree).compactMap { fileURL in
                let standardizedURL = fileURL.standardizedFileURL
                guard let data = try? Data(contentsOf: standardizedURL) else {
                    return nil
                }

                return (standardizedURL.path, data)
            }
        )
    }

    private func workspaceFileURLs(in nodes: [WorkspaceFileNode]) -> [URL] {
        nodes.flatMap { node in
            if node.isDirectory {
                workspaceFileURLs(in: node.children)
            } else {
                [node.url]
            }
        }
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let standardizedFileURL = fileURL.standardizedFileURL
        let standardizedRootURL = rootURL.standardizedFileURL
        let rootPath = standardizedRootURL.path
        let filePath = standardizedFileURL.path

        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }

        return standardizedFileURL.lastPathComponent
    }

    private func exercismStatusMessage(for status: ExercismCLI.Status) -> String {
        if !status.isInstalled {
            return """
            Exercism CLI is not installed.

            Install it on macOS with:
            brew install exercism
            """
        }

        if !status.hasToken {
            return """
            Exercism CLI is installed, but no API token is configured.

            Find your token at:
            https://exercism.org/settings/api_cli

            Then run:
            exercism configure --token=YOUR_TOKEN

            RustGoblin will reuse your current Exercism setup instead of rewriting it automatically.
            """
        }

        guard let workspaceURL = status.workspaceURL else {
            return """
            Exercism CLI is installed, but no workspace is configured.

            Configure it with:
            exercism configure --workspace=\"$HOME/Exercism\" --token=YOUR_TOKEN

            RustGoblin will import exercises from the configured Exercism workspace.
            """
        }

        return """
        Exercism CLI is ready.

        Executable:
        \(status.executableURL?.path ?? "Unavailable")

        Config:
        \(status.configFileURL.path)

        Workspace:
        \(workspaceURL.path)

        RustGoblin will download Exercism exercises into that workspace and then import them into the app library.
        """
    }

    private func promptLabel(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func resolveExercismDownloadInput(
        command: String,
        track: String,
        exercise: String
    ) throws -> (track: String, exercise: String) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCommand.isEmpty {
            return try parseExercismDownloadCommand(trimmedCommand)
        }

        let trimmedTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTrack.isEmpty, !trimmedExercise.isEmpty else {
            throw PromptValidationError.missingTrackOrExercise
        }

        return (trimmedTrack, trimmedExercise)
    }

    private func parseExercismDownloadCommand(_ command: String) throws -> (track: String, exercise: String) {
        let track = firstRegexCapture(
            pattern: #"--track(?:=|\s+)([A-Za-z0-9_-]+)"#,
            in: command
        )
        let exercise = firstRegexCapture(
            pattern: #"--exercise(?:=|\s+)([A-Za-z0-9_-]+)"#,
            in: command
        )

        guard let track, let exercise else {
            throw PromptValidationError.invalidExercismCommand
        }

        return (track, exercise)
    }

    private func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[captureRange])
    }

    private func showBlockingAlert(title: String, message: String, style: NSAlert.Style) {
        activateApplication()

        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func appendSessionMessage(_ message: String) {
        sessionLog.insert(
            "\(Date().formatted(date: .omitted, time: .shortened))  \(message)",
            at: 0
        )
    }
}

private final class PromptTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBezeled = true
        isBordered = true
        usesSingleLineMode = true
        lineBreakMode = .byClipping

        if let cell = cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
            cell.lineBreakMode = .byClipping
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        DispatchQueue.main.async { [weak self] in
            guard let self, let window else {
                return
            }

            window.makeFirstResponder(self)
        }
    }
}

private enum PromptValidationError: LocalizedError {
    case missingTrackOrExercise
    case invalidExercismCommand

    var errorDescription: String? {
        switch self {
        case .missingTrackOrExercise:
            return "Enter both a track and exercise slug, or paste a full Exercism download command."
        case .invalidExercismCommand:
            return "RustGoblin could not parse that Exercism command. Use a command like `exercism download --track=rust --exercise=hello-world`."
        }
    }
}
