import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class WorkspaceStore {
    private static let editorKeymapDefaultsKey = "editor-keymap-mode"

    var workspaceLibrary: [SavedWorkspaceRecord] = []
    var workspace: ExerciseWorkspace?
    var selectedWorkspaceRootPath: String?
    var selectedExerciseID: ExerciseDocument.ID?
    var selectedExplorerFileURL: URL?
    var selectedExplorerNodePath: String?
    var openTabs: [ActiveDocumentTab] = []
    var editorText: String = ""
    var explorerPreviewText: String = ""
    var currentDiffText: String = ""
    var editorKeymapMode: EditorKeymapMode = .standard
    var vimInputMode: VimInputMode = .insert
    var searchText: String = ""
    var explorerSearchText: String = ""
    var selectedDifficultyFilter: ExerciseDifficulty?
    var showsOnlyTestExercises: Bool = false
    var completionFilter: ExerciseCompletionFilter = .open
    var isWorkspacePickerPresented: Bool = false
    var workspacePickerSearchText: String = ""
    var workspacePickerFocusToken: Int = 0
    var consoleOutput: String = "Import a folder or a Rust file to start building your exercise workspace.\n"
    var sessionLog: [String] = []
    var diagnostics: [Diagnostic] = []
    var selectedConsoleTab: ConsoleTab = .output
    var terminalDisplayMode: TerminalDisplayMode = .split
    var runState: RunState = .idle
    var lastCommandDescription: String = ""
    var lastTerminationStatus: Int32?
    var isInspectorVisible: Bool = true
    var rightSidebarTab: RightSidebarTab = .inspector
    var rightSidebarWidth: CGFloat = RustGoblinTheme.Layout.inspectorWidth
    var isSolutionVisible: Bool = false
    var isEditorDirty: Bool = false
    var editorDisplayMode: EditorDisplayMode = .edit
    var contentDisplayMode: ContentDisplayMode = .split
    var sidebarMode: SidebarMode = .exercises
    var isCloneSheetPresented: Bool = false
    var cloneRepositoryURL: String = ""
    var cloneErrorMessage: String?
    var isCloningRepository: Bool = false
    var isSubmittingExercism: Bool = false
    var selectedChatSessionID: UUID?
    var chatComposerFocusToken: Int = 0
    var exerciseSearchFocusToken: Int = 0
    var explorerSearchFocusToken: Int = 0
    var explorerKeyboardFocusActive: Bool = false
    var expandedExplorerDirectoryPaths: Set<String> = []

    @ObservationIgnored private let importer: WorkspaceImporter
    @ObservationIgnored private let cargoRunner: CargoRunner
    @ObservationIgnored private let sourcePresentationBuilder: SourcePresentationBuilder
    @ObservationIgnored private let appPaths: AppStoragePaths
    @ObservationIgnored private let database: WorkspaceLibraryDatabase
    @ObservationIgnored private let repositoryCloner: RepositoryCloner
    @ObservationIgnored private let exercismCLI: ExercismCLI
    @ObservationIgnored private let fileChangeService: WorkspaceFileChangeService
    @ObservationIgnored private let baselineStore: WorkspaceBaselineStore
    @ObservationIgnored private let rustlingsWorkspaceScaffolder: RustlingsWorkspaceScaffolder
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isRestoringState = false
    @ObservationIgnored private var workspaceFileBaseline: [String: Data] = [:]
    @ObservationIgnored private var draftEditorTextByPath: [String: String] = [:]
    @ObservationIgnored private weak var chatStore: ChatStore?

    init(
        appPaths: AppStoragePaths = .live(),
        importer: WorkspaceImporter = WorkspaceImporter(),
        cargoRunner: CargoRunner = CargoRunner(),
        sourcePresentationBuilder: SourcePresentationBuilder = SourcePresentationBuilder(),
        database: WorkspaceLibraryDatabase? = nil,
        repositoryCloner: RepositoryCloner? = nil,
        exercismCLI: ExercismCLI? = nil,
        fileChangeService: WorkspaceFileChangeService = WorkspaceFileChangeService(),
        rustlingsWorkspaceScaffolder: RustlingsWorkspaceScaffolder = RustlingsWorkspaceScaffolder(),
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
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
        self.fileChangeService = fileChangeService
        self.baselineStore = WorkspaceBaselineStore(baselineLibraryURL: appPaths.baselineLibraryURL)
        self.rustlingsWorkspaceScaffolder = rustlingsWorkspaceScaffolder
        self.sessionLog = bootstrapMessages
        self.editorKeymapMode = Self.loadEditorKeymapMode(from: defaults)
        self.vimInputMode = self.editorKeymapMode == .vim ? .normal : .insert

        restorePersistedLibrary()
    }

    func attachChatStore(_ chatStore: ChatStore) {
        self.chatStore = chatStore
        chatStore.syncSelection(using: self)
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

    var showsTerminal: Bool {
        terminalDisplayMode != .hidden
    }

    var isTerminalMaximized: Bool {
        terminalDisplayMode == .maximized
    }

    var currentFileTree: [WorkspaceFileNode] {
        filteredFileTree(workspace?.fileTree ?? [])
    }

    var visibleExplorerFileCount: Int {
        countFiles(in: currentFileTree)
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

    var activeDocumentURL: URL? {
        selectedExplorerFileURL
    }

    var currentEditableSourceURL: URL? {
        guard let selectedExercise else {
            return nil
        }

        let activeURL = selectedExplorerFileURL?.standardizedFileURL ?? selectedExercise.sourceURL.standardizedFileURL
        guard activeURL == selectedExercise.sourceURL.standardizedFileURL else {
            return nil
        }

        return selectedExercise.sourceURL.standardizedFileURL
    }

    var isShowingDiffPreview: Bool {
        editorDisplayMode == .diff
    }

    var canToggleDiffMode: Bool {
        activeDocumentURL != nil
    }

    var canResetActiveDocument: Bool {
        activeDocumentURL != nil
    }

    var currentWorkspaceRecord: SavedWorkspaceRecord? {
        guard let selectedWorkspaceRootPath else {
            return workspaceLibrary.first
        }

        return workspaceLibrary.first { $0.rootPath == selectedWorkspaceRootPath }
    }

    var windowTitle: String {
        workspace?.title ?? "RustGoblin"
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

    var supportsTestExerciseFilter: Bool {
        currentWorkspaceRecord?.sourceKind == .exercism
            && (workspace?.exercises.contains { $0.fileRole == .tests } ?? false)
    }

    var availableDifficultyFilters: [ExerciseDifficulty] {
        []
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
            let isCompleted = isExerciseCompleted(exercise)
            let matchesCompletion: Bool
            switch completionFilter {
            case .open:
                matchesCompletion = !isCompleted
            case .done:
                matchesCompletion = isCompleted
            }
            let matchesTests = !showsOnlyTestExercises || exercise.fileRole == .tests
            let matchesQuery = trimmedQuery.isEmpty || [
                exercise.title,
                exercise.summary,
                exercise.sourceURL.lastPathComponent,
                currentWorkspaceRecord?.title ?? ""
            ].contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) })

            return matchesCompletion && matchesTests && matchesQuery
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
        if let selectedExercise {
            let trimmedHint = selectedExercise.hintContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedHint.isEmpty, trimmedHint != "No hints added for this exercise yet." {
                return selectedExercise.hintContent
            }
        }

        if isShowingMarkdownPreview {
            let trimmedPreview = explorerPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPreview.isEmpty {
                return trimmedPreview
            }
        }

        return "No hints added for this exercise yet."
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

    var canResetCurrentWorkspace: Bool {
        currentWorkspaceRecord != nil
    }

    var canDeleteCurrentWorkspace: Bool {
        currentWorkspaceRecord != nil
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

    func showNewWorkspacePrompt() {
        activateApplication()

        let alert = NSAlert()
        alert.messageText = "New Workspace"
        alert.informativeText = "Create a managed RustGoblin workspace for authoring custom Rustlings-style exercises."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let inputField = PromptTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        inputField.placeholderString = "algorithms-lab"
        inputField.stringValue = "workspace"
        inputField.isEditable = true
        inputField.isSelectable = true
        alert.accessoryView = inputField
        let alertWindow = alert.window
        alertWindow.initialFirstResponder = inputField
        DispatchQueue.main.async {
            alertWindow.makeFirstResponder(inputField)
            inputField.selectText(nil)
        }
        alertWindow.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        createEmptyWorkspace(named: inputField.stringValue)
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

        do {
            let managedWorkspace = try prepareWorkspaceForImport(from: url, sourceKind: sourceKind)
            loadWorkspace(
                at: managedWorkspace.rootURL,
                sourceKind: sourceKind,
                cloneURL: cloneURL,
                originPath: managedWorkspace.originPath,
                restoreState: true,
                refreshBaseline: true
            )
        } catch {
            consoleOutput = "Import failed: \(error.localizedDescription)\n"
            appendSessionMessage("Import failed for \(url.path)")
        }
    }

    func loadPersistedWorkspace(rootPath: String) {
        guard let record = workspaceLibrary.first(where: { $0.rootPath == rootPath }), !record.isMissing else {
            return
        }

        if isEditorDirty {
            saveSelectedExercise()
        }

        loadWorkspace(
            at: record.rootURL,
            sourceKind: record.sourceKind,
            cloneURL: record.cloneURL,
            originPath: record.originPath,
            restoreState: true,
            refreshBaseline: false
        )
        isWorkspacePickerPresented = false
    }

    func showWorkspacePalette() {
        isWorkspacePickerPresented = true
        workspacePickerFocusToken &+= 1
    }

    func hideWorkspacePalette() {
        isWorkspacePickerPresented = false
    }

    func selectExercise(id: ExerciseDocument.ID?) {
        guard let id, selectedExerciseID != id else {
            return
        }

        captureDraftForActiveEditableDocument()

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
        selectedExplorerNodePath = url.standardizedFileURL.path
        explorerKeyboardFocusActive = true
        registerOpenTab(url)
        activateDocument(at: url, persistState: true)
    }

    func clearConsoleOutput() {
        consoleOutput = ""
        if selectedConsoleTab != .output {
            selectedConsoleTab = .output
        }
    }

    func selectConsoleTab(_ tab: ConsoleTab) {
        if terminalDisplayMode == .hidden {
            terminalDisplayMode = .split
        }
        selectedConsoleTab = tab
    }

    func closeTab(_ tab: ActiveDocumentTab) {
        guard let closingIndex = openTabs.firstIndex(of: tab) else {
            return
        }

        if isEditorDirty,
           selectedExplorerFileURL?.standardizedFileURL == tab.url.standardizedFileURL,
           selectedExercise?.sourceURL.standardizedFileURL == tab.url.standardizedFileURL {
            saveSelectedExercise()
        }

        let isActiveTab = selectedExplorerFileURL?.standardizedFileURL == tab.url.standardizedFileURL
        openTabs.remove(at: closingIndex)

        guard isActiveTab else {
            persistCurrentWorkspaceSnapshot()
            return
        }

        if let replacement = replacementTab(afterClosingAt: closingIndex) {
            activateDocument(at: replacement.url, persistState: true)
        } else {
            clearActiveDocumentState()
            persistCurrentWorkspaceSnapshot()
        }
    }

    func closeActiveTab() {
        guard let activePath = selectedExplorerFileURL?.standardizedFileURL.path,
              let activeTab = openTabs.first(where: { $0.path == activePath }) else {
            return
        }

        closeTab(activeTab)
    }

    func activateNextTab() {
        guard let currentIndex = activeTabIndex else {
            return
        }

        let nextIndex = (currentIndex + 1) % openTabs.count
        activateTab(openTabs[nextIndex])
    }

    func activatePreviousTab() {
        guard let currentIndex = activeTabIndex else {
            return
        }

        let previousIndex = currentIndex == 0 ? openTabs.count - 1 : currentIndex - 1
        activateTab(openTabs[previousIndex])
    }

    func activateNumberedTab(_ number: Int) {
        guard !openTabs.isEmpty else {
            return
        }

        let targetIndex: Int
        if number == 0 {
            targetIndex = openTabs.count - 1
        } else {
            targetIndex = number - 1
        }

        guard openTabs.indices.contains(targetIndex) else {
            return
        }

        activateTab(openTabs[targetIndex])
    }

    func saveSelectedExercise() {
        guard
            var workspace,
            let selectedExerciseID,
            let selectedIndex = workspace.exercises.firstIndex(where: { $0.id == selectedExerciseID }),
            let editableURL = currentEditableSourceURL,
            editableURL.standardizedFileURL == workspace.exercises[selectedIndex].sourceURL.standardizedFileURL
        else {
            return
        }

        let selectedExercise = workspace.exercises[selectedIndex]
        let sourcePath = selectedExercise.sourceURL.standardizedFileURL.path
        let currentText = draftEditorTextByPath[sourcePath] ?? editorText

        do {
            let rebuiltSource = selectedExercise.presentation.rebuild(with: currentText)
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
            draftEditorTextByPath.removeValue(forKey: sourcePath)
            editorText = updatedPresentation.visibleSource
            isEditorDirty = false
            editorDisplayMode = .edit
            currentDiffText = ""
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
        persistCurrentWorkspaceSnapshot()
    }

    func selectRightSidebarTab(_ tab: RightSidebarTab) {
        if !isInspectorVisible {
            isInspectorVisible = true
        }

        guard rightSidebarTab != tab else {
            persistCurrentWorkspaceSnapshot()
            return
        }

        rightSidebarTab = tab
        persistCurrentWorkspaceSnapshot()
    }

    func setRightSidebarWidth(_ width: CGFloat) {
        let fixedWidth = RustGoblinTheme.Layout.inspectorWidth
        _ = width
        guard abs(rightSidebarWidth - fixedWidth) > 0.5 else {
            return
        }

        rightSidebarWidth = fixedWidth
        persistCurrentWorkspaceSnapshot()
    }

    func focusChatComposer() {
        selectRightSidebarTab(.chat)
        chatComposerFocusToken += 1
        persistCurrentWorkspaceSnapshot()
    }

    func focusInspectorSidebar() {
        selectRightSidebarTab(.inspector)
    }

    func toggleTerminalVisibility() {
        terminalDisplayMode = terminalDisplayMode == .hidden ? .split : .hidden
        persistCurrentWorkspaceSnapshot()
    }

    func toggleTerminalMaximize() {
        terminalDisplayMode = terminalDisplayMode == .maximized ? .split : .maximized
        persistCurrentWorkspaceSnapshot()
    }

    func toggleRightSidebarVisibility() {
        toggleInspector()
    }

    func toggleLeftColumnVisibility() {
        toggleProblemPaneVisibility()
    }

    func showExplorerAndFocusSearch() {
        if !showsProblemPane {
            contentDisplayMode = .split
        }
        sidebarMode = .explorer
        explorerKeyboardFocusActive = false
        explorerSearchFocusToken += 1
        persistCurrentWorkspaceSnapshot()
    }

    func showExerciseLibraryAndFocusSearch() {
        if !showsProblemPane {
            contentDisplayMode = .split
        }
        sidebarMode = .exercises
        explorerKeyboardFocusActive = false
        exerciseSearchFocusToken += 1
        persistCurrentWorkspaceSnapshot()
    }

    func createEmptyWorkspace(named rawName: String) {
        do {
            let normalizedName = sanitizeWorkspaceName(rawName)
            let workspaceRootURL = nextCreatedWorkspaceURL(named: normalizedName)
            try rustlingsWorkspaceScaffolder.createEmptyWorkspace(named: normalizedName, at: workspaceRootURL)

            loadWorkspace(
                at: workspaceRootURL,
                sourceKind: .created,
                cloneURL: nil,
                originPath: nil,
                restoreState: false,
                refreshBaseline: true
            )

            consoleOutput = "Created workspace: \(normalizedName)\n"
            appendSessionMessage("Workspace created for \(normalizedName)")
        } catch {
            showBlockingAlert(
                title: "New Workspace",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    func handleChatSlashCommand(_ input: String) async throws -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return nil
        }

        let components = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let command = components.first?.lowercased() ?? trimmed.lowercased()
        let argument = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch command {
        case "/challenge":
            return try await createWorkspaceChallenge(named: argument)
        default:
            throw NSError(
                domain: "WorkspaceStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown chat command `\(command)`. Supported commands: `/challenge <name>`."] 
            )
        }
    }

    func setExplorerKeyboardFocus(active: Bool) {
        explorerKeyboardFocusActive = active
    }

    func toggleExplorerDirectory(_ node: WorkspaceFileNode) {
        guard node.isDirectory else {
            return
        }

        let path = node.url.standardizedFileURL.path
        selectedExplorerNodePath = path
        explorerKeyboardFocusActive = true

        if expandedExplorerDirectoryPaths.contains(path) {
            expandedExplorerDirectoryPaths.remove(path)
        } else {
            expandedExplorerDirectoryPaths.insert(path)
        }
    }

    func selectExplorerNode(_ node: WorkspaceFileNode) {
        selectedExplorerNodePath = node.url.standardizedFileURL.path
        explorerKeyboardFocusActive = true
    }

    func handleExplorerKey(_ key: String) {
        guard sidebarMode == .explorer, showsProblemPane else {
            return
        }

        switch key.lowercased() {
        case "j":
            moveExplorerSelection(delta: 1)
        case "k":
            moveExplorerSelection(delta: -1)
        case "h":
            collapseExplorerSelection()
        case "l":
            openExplorerSelection()
        default:
            break
        }
    }

    func selectSidebarMode(_ mode: SidebarMode) {
        guard sidebarMode != mode else {
            return
        }

        sidebarMode = mode
        persistCurrentWorkspaceSnapshot()
    }

    func selectDifficultyFilter(_ filter: ExerciseDifficulty?) {
        selectedDifficultyFilter = filter
        persistCurrentWorkspaceSnapshot()
    }

    func toggleTestsExerciseFilter() {
        guard supportsTestExerciseFilter else {
            if showsOnlyTestExercises {
                showsOnlyTestExercises = false
                persistCurrentWorkspaceSnapshot()
            }
            return
        }

        showsOnlyTestExercises.toggle()
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

    func persistExplorerSearchTextChange() {
        explorerKeyboardFocusActive = false
        selectFirstVisibleExplorerEntry()
    }

    func moveExplorerSelectionDown() {
        moveExplorerSelection(delta: 1)
    }

    func moveExplorerSelectionUp() {
        moveExplorerSelection(delta: -1)
    }

    func activateSelectedExplorerEntry() {
        openExplorerSelection()
    }

    func toggleEditorKeymapMode() {
        setEditorKeymapMode(editorKeymapMode == .standard ? .vim : .standard)
    }

    func setEditorKeymapMode(_ mode: EditorKeymapMode) {
        guard editorKeymapMode != mode else {
            vimInputMode = mode == .vim ? .normal : .insert
            return
        }

        editorKeymapMode = mode
        vimInputMode = mode == .vim ? .normal : .insert
        defaults.set(mode.rawValue, forKey: Self.editorKeymapDefaultsKey)
    }

    func setVimInputMode(_ mode: VimInputMode) {
        guard editorKeymapMode == .vim else {
            vimInputMode = .insert
            return
        }
        vimInputMode = mode
    }

    func toggleSolutionVisibility() {
        isSolutionVisible.toggle()
    }

    func handleEditorTextChange() {
        guard let editableURL = currentEditableSourceURL else {
            isEditorDirty = false
            return
        }

        let baseText = selectedExercise?.presentation.visibleSource ?? ""
        let path = editableURL.standardizedFileURL.path

        if editorText == baseText {
            draftEditorTextByPath.removeValue(forKey: path)
            isEditorDirty = false
        } else {
            draftEditorTextByPath[path] = editorText
            isEditorDirty = true
        }
    }

    func resetSelectedExercise() {
        Task {
            await restoreActiveDocument()
        }
    }

    func resetCurrentWorkspace() {
        guard let record = currentWorkspaceRecord else {
            return
        }

        let message = """
        This will discard all current changes for “\(record.title)” and restore the workspace back to its original imported state.

        This action is destructive.
        """

        guard confirmDestructiveAction(
            title: "Reset Workspace",
            message: message,
            buttonTitle: "Reset Workspace"
        ) else {
            return
        }

        Task {
            await performWorkspaceReset(record)
        }
    }

    func deleteCurrentWorkspace() {
        guard let record = currentWorkspaceRecord else {
            return
        }

        let deletesFiles = appPaths.containsManagedWorkspace(record.rootURL)
        let message: String
        if deletesFiles {
            message = """
            This will permanently delete the managed workspace files for “\(record.title)” and remove all related RustGoblin data.

            This action is destructive.
            """
        } else {
            message = """
            This workspace lives outside RustGoblin managed storage. RustGoblin will remove it from the library and delete its saved data, but it will leave the original files on disk untouched.

            This action is destructive.
            """
        }

        guard confirmDestructiveAction(
            title: deletesFiles ? "Delete Workspace" : "Remove Workspace",
            message: message,
            buttonTitle: deletesFiles ? "Delete Workspace" : "Remove Workspace"
        ) else {
            return
        }

        Task {
            await performWorkspaceDeletion(record)
        }
    }

    func toggleDiffMode() {
        guard canToggleDiffMode else {
            return
        }

        if editorDisplayMode == .diff {
            editorDisplayMode = .edit
            currentDiffText = ""
            return
        }

        Task {
            await prepareDiffForActiveDocument()
        }
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
                    originPath: mostRecentAvailableWorkspace.originPath,
                    restoreState: true,
                    refreshBaseline: false
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
        originPath: String?,
        restoreState: Bool,
        refreshBaseline: Bool
    ) {
        do {
            var loadedWorkspace = try importer.loadWorkspace(from: url)
            let rootPath = loadedWorkspace.rootURL.standardizedFileURL.path
            let progressLookup = try database.fetchProgress(for: rootPath)
            applyStoredProgress(progressLookup, to: &loadedWorkspace)

            if refreshBaseline {
                try baselineStore.captureBaseline(from: loadedWorkspace.rootURL)
            }

            workspace = loadedWorkspace
            workspaceFileBaseline = baselineStore.loadBaselineData(for: loadedWorkspace)
            if workspaceFileBaseline.isEmpty {
                workspaceFileBaseline = snapshotWorkspaceFiles(for: loadedWorkspace)
            }
            draftEditorTextByPath = [:]
            selectedWorkspaceRootPath = rootPath
            diagnostics = []
            selectedConsoleTab = .output
            runState = .idle
            lastCommandDescription = ""
            lastTerminationStatus = nil
            isSolutionVisible = false
            editorDisplayMode = .edit
            currentDiffText = ""
            contentDisplayMode = .split
            terminalDisplayMode = .split
            explorerSearchText = ""
            selectedExplorerNodePath = nil
            explorerKeyboardFocusActive = false
            expandedExplorerDirectoryPaths = allDirectoryPaths(in: loadedWorkspace.fileTree)
            consoleOutput = "Imported \(loadedWorkspace.exercises.count) exercise(s) from \(loadedWorkspace.rootURL.lastPathComponent).\n"
            appendSessionMessage("Workspace loaded from \(loadedWorkspace.rootURL.path)")

            let existingRecord = try database.fetchWorkspace(rootPath: rootPath)
            let record = SavedWorkspaceRecord(
                rootPath: rootPath,
                title: loadedWorkspace.title,
                sourceKind: sourceKind,
                cloneURL: cloneURL ?? existingRecord?.cloneURL,
                originPath: originPath ?? existingRecord?.originPath,
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

            chatStore?.syncSelection(using: self)

            persistCurrentWorkspaceSnapshot()
        } catch {
            workspace = nil
            workspaceFileBaseline = [:]
            draftEditorTextByPath = [:]
            selectedWorkspaceRootPath = nil
            selectedExerciseID = nil
            clearActiveDocumentState()
            isEditorDirty = false
            consoleOutput = "Import failed: \(error.localizedDescription)\n"
            appendSessionMessage("Import failed for \(url.path)")
            chatStore?.syncSelection(using: self)
        }
    }

    private func applySavedState(_ state: WorkspaceSessionState, in workspace: ExerciseWorkspace) {
        isRestoringState = true
        defer { isRestoringState = false }

        searchText = state.searchQuery
        selectedDifficultyFilter = state.difficultyFilter
        showsOnlyTestExercises = supportsTestExerciseFilter ? state.showsOnlyTestExercises : false
        completionFilter = state.completionFilter
        sidebarMode = state.sidebarMode
        rightSidebarTab = state.rightSidebarTab
        isInspectorVisible = state.isInspectorVisible
        rightSidebarWidth = RustGoblinTheme.Layout.inspectorWidth
        terminalDisplayMode = state.terminalDisplayMode
        selectedChatSessionID = state.selectedChatSessionID
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
        let sourcePath = selectedExercise?.sourceURL.standardizedFileURL.path
        editorText = sourcePath.flatMap { draftEditorTextByPath[$0] } ?? selectedExercise?.presentation.visibleSource ?? ""
        explorerPreviewText = ""
        isEditorDirty = sourcePath.map { draftEditorTextByPath[$0] != nil } ?? false
        editorDisplayMode = .edit
        currentDiffText = ""
        isSolutionVisible = false
        selectedChatSessionID = nil

        if let sourceURL = selectedExercise?.sourceURL {
            selectedExplorerFileURL = sourceURL
            selectedExplorerNodePath = sourceURL.standardizedFileURL.path
            registerOpenTab(sourceURL)
        }

        chatStore?.syncSelection(using: self)
    }

    private func activateDocument(at url: URL, persistState: Bool) {
        guard let workspace else {
            return
        }

        captureDraftForActiveEditableDocument()
        selectedExplorerFileURL = url.standardizedFileURL
        selectedExplorerNodePath = url.standardizedFileURL.path
        registerOpenTab(url)
        editorDisplayMode = .edit
        currentDiffText = ""

        if let matchingExercise = workspace.exercises.first(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            selectedExerciseID = matchingExercise.id
            let sourcePath = matchingExercise.sourceURL.standardizedFileURL.path
            editorText = draftEditorTextByPath[sourcePath] ?? matchingExercise.presentation.visibleSource
            explorerPreviewText = ""
            isEditorDirty = draftEditorTextByPath[sourcePath] != nil
            selectedChatSessionID = nil
        } else {
            explorerPreviewText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            isEditorDirty = false
        }

        chatStore?.syncSelection(using: self)

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

    private func replacementTab(afterClosingAt closingIndex: Int) -> ActiveDocumentTab? {
        guard !openTabs.isEmpty else {
            return nil
        }

        if closingIndex < openTabs.count {
            return openTabs[closingIndex]
        }

        return openTabs.last
    }

    private var activeTabIndex: Int? {
        guard let activePath = selectedExplorerFileURL?.standardizedFileURL.path else {
            return nil
        }

        return openTabs.firstIndex(where: { $0.path == activePath })
    }

    private func clearActiveDocumentState() {
        selectedExplorerFileURL = nil
        selectedExplorerNodePath = nil
        explorerPreviewText = ""
        openTabs = []
        editorText = ""
        currentDiffText = ""
        editorDisplayMode = .edit
        explorerKeyboardFocusActive = false
        selectedChatSessionID = nil
        chatStore?.syncSelection(using: self)
    }

    private func captureDraftForActiveEditableDocument() {
        guard let editableURL = currentEditableSourceURL else {
            return
        }

        let path = editableURL.standardizedFileURL.path
        let baseText = selectedExercise?.presentation.visibleSource ?? ""

        if editorText == baseText {
            draftEditorTextByPath.removeValue(forKey: path)
        } else {
            draftEditorTextByPath[path] = editorText
        }
    }

    private func currentDocumentText(for url: URL) -> String {
        let standardizedURL = url.standardizedFileURL

        if standardizedURL == currentEditableSourceURL?.standardizedFileURL {
            return draftEditorTextByPath[standardizedURL.path] ?? editorText
        }

        if standardizedURL == selectedExplorerFileURL?.standardizedFileURL, isShowingReadonlyPreview {
            return explorerPreviewText
        }

        return (try? String(contentsOf: standardizedURL, encoding: .utf8)) ?? ""
    }

    private func originalText(for url: URL) async throws -> String {
        let standardizedURL = url.standardizedFileURL

        if let gitRoot = try await fileChangeService.gitRepositoryRoot(for: standardizedURL),
           let gitHeadText = try await fileChangeService.gitHeadContent(for: standardizedURL, repositoryRootURL: gitRoot) {
            return gitHeadText
        }

        if let baselineData = workspaceFileBaseline[standardizedURL.path] {
            return String(decoding: baselineData, as: UTF8.self)
        }

        return ""
    }

    private func prepareDiffForActiveDocument() async {
        guard let activeDocumentURL else {
            return
        }

        do {
            let original = try await originalText(for: activeDocumentURL)
            let modified = currentDocumentText(for: activeDocumentURL)
            let diff = try await fileChangeService.diff(
                original: original,
                modified: modified,
                originalLabel: "original",
                modifiedLabel: "current"
            )

            currentDiffText = diff.isEmpty ? "No changes in this file." : diff
            editorDisplayMode = .diff
        } catch {
            currentDiffText = "Diff failed: \(error.localizedDescription)"
            editorDisplayMode = .diff
        }
    }

    private func restoreActiveDocument() async {
        guard let activeDocumentURL else {
            return
        }

        do {
            if let gitRoot = try await fileChangeService.gitRepositoryRoot(for: activeDocumentURL) {
                try await fileChangeService.restoreFileFromGit(activeDocumentURL, repositoryRootURL: gitRoot)
            } else if let baselineData = workspaceFileBaseline[activeDocumentURL.standardizedFileURL.path] {
                try baselineData.write(to: activeDocumentURL, options: .atomic)
            } else {
                try "".write(to: activeDocumentURL, atomically: true, encoding: .utf8)
            }

            reloadDocumentState(afterExternalChangeAt: activeDocumentURL)
            appendSessionMessage("Restored \(activeDocumentURL.lastPathComponent)")
        } catch {
            consoleOutput += "Restore failed: \(error.localizedDescription)\n"
            appendSessionMessage("Restore failed for \(activeDocumentURL.lastPathComponent)")
        }
    }

    private func reloadDocumentState(afterExternalChangeAt url: URL) {
        guard var workspace else {
            return
        }

        let standardizedURL = url.standardizedFileURL
        draftEditorTextByPath.removeValue(forKey: standardizedURL.path)
        currentDiffText = ""
        editorDisplayMode = .edit

        if let selectedIndex = workspace.exercises.firstIndex(where: { $0.sourceURL.standardizedFileURL == standardizedURL }),
           let rebuiltSource = try? String(contentsOf: standardizedURL, encoding: .utf8) {
            let updatedPresentation = sourcePresentationBuilder.build(from: rebuiltSource)
            let existingChecks = workspace.exercises[selectedIndex].checks
            workspace.exercises[selectedIndex].sourceCode = rebuiltSource
            workspace.exercises[selectedIndex].presentation = updatedPresentation
            workspace.exercises[selectedIndex].checks = mergeCheckStatuses(
                existing: existingChecks,
                replacement: updatedPresentation.hiddenChecks
            )
            self.workspace = workspace
            editorText = updatedPresentation.visibleSource
            isEditorDirty = false
        } else {
            explorerPreviewText = (try? String(contentsOf: standardizedURL, encoding: .utf8)) ?? ""
            isEditorDirty = false
        }

        persistCurrentWorkspaceSnapshot()
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
                isInspectorVisible: isInspectorVisible,
                rightSidebarTab: rightSidebarTab,
                rightSidebarWidth: rightSidebarWidth,
                terminalDisplayMode: terminalDisplayMode,
                searchQuery: searchText,
                difficultyFilter: selectedDifficultyFilter,
                showsOnlyTestExercises: showsOnlyTestExercises,
                completionFilter: completionFilter,
                selectedChatSessionID: selectedChatSessionID
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

    func persistChatSelection() {
        persistCurrentWorkspaceSnapshot()
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

            appendSessionMessage("$ \(result.commandDescription)")

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

    private func filteredFileTree(_ nodes: [WorkspaceFileNode]) -> [WorkspaceFileNode] {
        let trimmedQuery = explorerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return nodes
        }

        let normalizedQuery = trimmedQuery.lowercased()
        return nodes.compactMap { filterFileNode($0, query: normalizedQuery) }
    }

    private func filterFileNode(_ node: WorkspaceFileNode, query: String) -> WorkspaceFileNode? {
        let pathMatches = node.url.path.lowercased().contains(query)
        let nameMatches = node.name.lowercased().contains(query)

        if node.isDirectory {
            let filteredChildren = node.children.compactMap { filterFileNode($0, query: query) }
            guard nameMatches || pathMatches || !filteredChildren.isEmpty else {
                return nil
            }

            return WorkspaceFileNode(
                id: node.id,
                url: node.url,
                name: node.name,
                isDirectory: true,
                children: filteredChildren
            )
        }

        return (nameMatches || pathMatches) ? node : nil
    }

    private func countFiles(in nodes: [WorkspaceFileNode]) -> Int {
        nodes.reduce(0) { partial, node in
            partial + (node.isDirectory ? countFiles(in: node.children) : 1)
        }
    }

    private func allDirectoryPaths(in nodes: [WorkspaceFileNode]) -> Set<String> {
        Set(nodes.flatMap(directoryPaths(for:)))
    }

    private func directoryPaths(for node: WorkspaceFileNode) -> [String] {
        guard node.isDirectory else {
            return []
        }

        return [node.url.standardizedFileURL.path] + node.children.flatMap(directoryPaths(for:))
    }

    private func visibleExplorerEntries() -> [ExplorerVisibleEntry] {
        flattenExplorerNodes(currentFileTree, depth: 0, parentPath: nil)
    }

    private func flattenExplorerNodes(
        _ nodes: [WorkspaceFileNode],
        depth: Int,
        parentPath: String?
    ) -> [ExplorerVisibleEntry] {
        let isFiltering = !explorerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return nodes.flatMap { node in
            let path = node.url.standardizedFileURL.path
            let entry = ExplorerVisibleEntry(node: node, depth: depth, parentPath: parentPath)
            let isExpanded = isFiltering || expandedExplorerDirectoryPaths.contains(path)

            if node.isDirectory, isExpanded {
                return [entry] + flattenExplorerNodes(node.children, depth: depth + 1, parentPath: path)
            }

            return [entry]
        }
    }

    private func moveExplorerSelection(delta: Int) {
        let entries = visibleExplorerEntries()
        guard !entries.isEmpty else {
            return
        }

        let currentIndex = entries.firstIndex(where: { $0.path == selectedExplorerNodePath }) ?? (delta > 0 ? -1 : entries.count)
        let targetIndex = min(max(currentIndex + delta, 0), entries.count - 1)
        let entry = entries[targetIndex]
        selectedExplorerNodePath = entry.path
        explorerKeyboardFocusActive = true
    }

    private func selectFirstVisibleExplorerEntry() {
        let entries = visibleExplorerEntries()
        selectedExplorerNodePath = entries.first?.path
    }

    private func collapseExplorerSelection() {
        let entries = visibleExplorerEntries()
        guard let selectedPath = selectedExplorerNodePath,
              let entry = entries.first(where: { $0.path == selectedPath }) else {
            return
        }

        if entry.node.isDirectory, expandedExplorerDirectoryPaths.contains(entry.path) {
            expandedExplorerDirectoryPaths.remove(entry.path)
            return
        }

        if let parentPath = entry.parentPath {
            selectedExplorerNodePath = parentPath
        }
    }

    private func openExplorerSelection() {
        let entries = visibleExplorerEntries()
        guard let selectedPath = selectedExplorerNodePath,
              let entry = entries.first(where: { $0.path == selectedPath }) else {
            return
        }

        if entry.node.isDirectory {
            if !expandedExplorerDirectoryPaths.contains(entry.path) {
                expandedExplorerDirectoryPaths.insert(entry.path)
                return
            }

            if let child = entries.first(where: { $0.parentPath == entry.path }) {
                selectedExplorerNodePath = child.path
            }
            return
        }

        openExplorerFile(entry.node.url)
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

    private func prepareWorkspaceForImport(
        from url: URL,
        sourceKind: WorkspaceSourceKind
    ) throws -> (rootURL: URL, originPath: String?) {
        let originRootURL = normalizedWorkspaceRoot(for: url)

        if appPaths.containsManagedWorkspace(originRootURL) || sourceKind == .cloned {
            return (originRootURL, nil)
        }

        let managedRootURL = managedWorkspaceURL(for: originRootURL, sourceKind: sourceKind)
        try replaceWorkspaceContents(from: originRootURL, to: managedRootURL)
        return (managedRootURL, originRootURL.path)
    }

    private func normalizedWorkspaceRoot(for url: URL) -> URL {
        if url.pathExtension.lowercased() == "rs" {
            return url.deletingLastPathComponent().standardizedFileURL
        }

        return url.standardizedFileURL
    }

    private func managedWorkspaceURL(for sourceRootURL: URL, sourceKind: WorkspaceSourceKind) -> URL {
        let containerURL: URL
        switch sourceKind {
        case .imported:
            containerURL = appPaths.importedLibraryURL
        case .cloned:
            containerURL = appPaths.cloneLibraryURL
        case .exercism:
            containerURL = appPaths.exercismLibraryURL
        case .created:
            containerURL = appPaths.createdWorkspaceLibraryURL
        }

        let slug = sourceRootURL.lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let digest = sourceRootURL.standardizedFileURL.path
            .utf8
            .reduce(into: 5381) { hash, byte in
                hash = ((hash << 5) &+ hash) &+ Int(byte)
            }
        let identifier = String(format: "%08x", abs(digest))
        let directoryName = "\(slug.isEmpty ? "workspace" : slug)-\(identifier)"
        return containerURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func replaceWorkspaceContents(from sourceRootURL: URL, to destinationRootURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationRootURL.path) {
            try fileManager.removeItem(at: destinationRootURL)
        }

        try fileManager.createDirectory(
            at: destinationRootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceRootURL, to: destinationRootURL)
    }

    private func createWorkspaceChallenge(named rawName: String) async throws -> String {
        guard let workspace, let record = currentWorkspaceRecord else {
            throw NSError(
                domain: "WorkspaceStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Open or create a workspace before using `/challenge`."] 
            )
        }

        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(
                domain: "WorkspaceStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Usage: `/challenge lru cache`"] 
            )
        }

        let result = try await rustlingsWorkspaceScaffolder.createChallenge(
            named: trimmedName,
            in: workspace.rootURL,
            providerManager: chatStore?.providerManager
        )

        loadWorkspace(
            at: workspace.rootURL,
            sourceKind: record.sourceKind,
            cloneURL: record.cloneURL,
            originPath: record.originPath,
            restoreState: false,
            refreshBaseline: true
        )

        if let createdExercise = self.workspace?.exercises.first(where: {
            $0.sourceURL.standardizedFileURL == result.exerciseURL.standardizedFileURL
        }) {
            applySelection(for: createdExercise.id)
            registerOpenTab(createdExercise.sourceURL)
            activateDocument(at: createdExercise.sourceURL, persistState: true)
        }

        appendSessionMessage("Created challenge \(result.slug)")

        var summaryLines = [
            "Created `\(result.slug)` in the current workspace.",
            "",
            "- Exercise: `\(relativePath(for: result.exerciseURL, rootURL: workspace.rootURL))`",
            "- Solution: `\(relativePath(for: result.solutionURL, rootURL: workspace.rootURL))`",
            "- Updated: `info.toml`"
        ]

        if let devUpdateMessage = result.devUpdateMessage, !devUpdateMessage.isEmpty {
            summaryLines += [
                "",
                "`rustlings dev update` / `rustlings dev check` output:",
                "```text",
                devUpdateMessage,
                "```"
            ]
        }

        return summaryLines.joined(separator: "\n")
    }

    private func performWorkspaceReset(_ record: SavedWorkspaceRecord) async {
        let rootURL = record.rootURL

        do {
            if baselineStore.hasBaseline(for: rootURL) {
                try baselineStore.restoreBaseline(to: rootURL)
            } else if let originURL = record.originURL, FileManager.default.fileExists(atPath: originURL.path) {
                try replaceWorkspaceContents(from: originURL, to: rootURL)
                try baselineStore.captureBaseline(from: rootURL)
            } else if record.sourceKind == .cloned, let cloneURL = record.cloneURL {
                _ = try await repositoryCloner.clone(
                    urlString: cloneURL,
                    destinationURL: rootURL,
                    replaceExisting: true
                )
                try baselineStore.captureBaseline(from: rootURL)
            } else {
                throw NSError(
                    domain: "WorkspaceStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "RustGoblin has no original baseline or recovery source for this workspace."]
                )
            }

            loadWorkspace(
                at: rootURL,
                sourceKind: record.sourceKind,
                cloneURL: record.cloneURL,
                originPath: record.originPath,
                restoreState: true,
                refreshBaseline: false
            )
            consoleOutput += "Workspace reset: \(record.title)\n"
            appendSessionMessage("Workspace reset for \(record.title)")
        } catch {
            showBlockingAlert(
                title: "Reset Workspace",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func performWorkspaceDeletion(_ record: SavedWorkspaceRecord) async {
        do {
            let isManaged = appPaths.containsManagedWorkspace(record.rootURL)
            if isManaged, FileManager.default.fileExists(atPath: record.rootURL.path) {
                try FileManager.default.removeItem(at: record.rootURL)
            }

            try? baselineStore.deleteBaseline(for: record.rootURL)
            try database.deleteWorkspace(rootPath: record.rootPath)

            workspaceLibrary.removeAll { $0.rootPath == record.rootPath }

            if selectedWorkspaceRootPath == record.rootPath {
                clearCurrentWorkspaceState()

                if let nextRecord = workspaceLibrary.first(where: { !$0.isMissing }) {
                    loadWorkspace(
                        at: nextRecord.rootURL,
                        sourceKind: nextRecord.sourceKind,
                        cloneURL: nextRecord.cloneURL,
                        originPath: nextRecord.originPath,
                        restoreState: true,
                        refreshBaseline: false
                    )
                }
            }

            consoleOutput += "Workspace removed: \(record.title)\n"
            appendSessionMessage("Workspace removed for \(record.title)")
        } catch {
            showBlockingAlert(
                title: "Delete Workspace",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func clearCurrentWorkspaceState() {
        workspace = nil
        selectedWorkspaceRootPath = nil
        selectedExerciseID = nil
        workspaceFileBaseline = [:]
        draftEditorTextByPath = [:]
        diagnostics = []
        runState = .idle
        lastCommandDescription = ""
        lastTerminationStatus = nil
        searchText = ""
        explorerSearchText = ""
        clearActiveDocumentState()
        isEditorDirty = false
        selectedChatSessionID = nil
        chatStore?.syncSelection(using: self)
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

    private func confirmDestructiveAction(title: String, message: String, buttonTitle: String) -> Bool {
        activateApplication()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: buttonTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func appendSessionMessage(_ message: String) {
        sessionLog.insert(
            "\(Date().formatted(date: .omitted, time: .shortened))  \(message)",
            at: 0
        )
    }

    private func sanitizeWorkspaceName(_ rawName: String) -> String {
        let normalized = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: " ")

        guard !normalized.isEmpty else {
            return "workspace"
        }

        return normalized
    }

    private func nextCreatedWorkspaceURL(named rawName: String) -> URL {
        let slug = rawName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        let baseName = slug.isEmpty ? "workspace" : slug
        var candidateURL = appPaths.createdWorkspaceLibraryURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidateURL.path) {
            candidateURL = appPaths.createdWorkspaceLibraryURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidateURL
    }
}

private extension WorkspaceStore {
    static func loadEditorKeymapMode(from defaults: UserDefaults) -> EditorKeymapMode {
        guard
            let rawValue = defaults.string(forKey: editorKeymapDefaultsKey),
            let mode = EditorKeymapMode(rawValue: rawValue)
        else {
            return .standard
        }

        return mode
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

private struct ExplorerVisibleEntry {
    let node: WorkspaceFileNode
    let depth: Int
    let parentPath: String?

    var path: String {
        node.url.standardizedFileURL.path
    }
}
