import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - Focus tracking for keyboard shortcut ping-pong

enum FocusTarget: Equatable {
    case editor
    case explorerSearch
    case exerciseSearch
    case exercismSearch
    case todo
    case chat
    case inspectorList
    case terminal
}

@Observable
@MainActor
final class WorkspaceStore {


    var workspaceLibrary: [SavedWorkspaceRecord] = []
    var workspace: ExerciseWorkspace?
    var selectedWorkspaceRootPath: String?
    var selectedExerciseID: ExerciseDocument.ID?
    // MARK: - Explorer State (Forwarded to ExplorerStore)
    var selectedExplorerFileURL: URL? {
        get { explorerStore.selectedFileURL }
        set { explorerStore.selectedFileURL = newValue }
    }
    var selectedExplorerNodePath: String? {
        get { explorerStore.selectedNodePath }
        set { explorerStore.selectedNodePath = newValue }
    }
    var openTabs: [ActiveDocumentTab] {
        get { explorerStore.openTabs }
        set { explorerStore.openTabs = newValue }
    }
    // MARK: - Editor State (Forwarded to EditorStateStore)
    var editorText: String {
        get { editorStore.text }
        set { editorStore.text = newValue }
    }
    var editorCursorLine: Int {
        get { editorStore.cursorLine }
        set { editorStore.cursorLine = newValue }
    }
    var editorCursorOffset: Int {
        get { editorStore.cursorOffset }
        set { editorStore.cursorOffset = newValue }
    }
    var cursorPositionByPath: [String: Int] {
        get { editorStore.cursorPositionByPath }
        set { editorStore.cursorPositionByPath = newValue }
    }
    var restoreCursorToken: Int {
        get { editorStore.restoreCursorToken }
        set { editorStore.restoreCursorToken = newValue }
    }
    var restoreCursorOffset: Int? {
        get { editorStore.restoreCursorOffset }
        set { editorStore.restoreCursorOffset = newValue }
    }
    var explorerPreviewText: String {
        get { explorerStore.previewText }
        set { explorerStore.previewText = newValue }
    }
    var currentDiffText: String = ""

    var searchText: String = ""
    var explorerSearchText: String {
        get { explorerStore.searchText }
        set { explorerStore.searchText = newValue }
    }
    var selectedDifficultyFilter: ExerciseDifficulty?
    var showsOnlyTestExercises: Bool = false
    var completionFilter: ExerciseCompletionFilter = .open
    var isWorkspacePickerPresented: Bool = false
    var workspacePickerSearchText: String = ""
    var workspacePickerFocusToken: Int = 0
    var consoleOutput: String = "Import a folder or a Rust file to start building your exercise workspace.\n" {
        didSet {
            if consoleOutput.count > 100_000 {
                consoleOutput = String(consoleOutput.suffix(90_000))
            }
        }
    }
    var sessionLog: [String] = []

    var rightSidebarTab: RightSidebarTab = .inspector
    var rightSidebarWidth: CGFloat = CrabTimeTheme.Layout.inspectorWidth
    var isSolutionVisible: Bool = false
    var isEditorDirty: Bool {
        get { editorStore.isDirty }
        set { editorStore.isDirty = newValue }
    }
    /// Paths of exercise files currently being AI-enriched in the background.
    var enrichingExercisePaths: Set<String> = []
    var isCloneSheetPresented: Bool = false
    var cloneRepositoryURL: String = ""
    var cloneErrorMessage: String?
    var isCloningRepository: Bool = false
    var selectedChatSessionID: UUID?
    var chatComposerFocusToken: Int = 0
    var exerciseSearchFocusToken: Int = 0
    var exercismSearchFocusToken: Int = 0
    var explorerSearchFocusToken: Int {
        get { explorerStore.searchFocusToken }
        set { explorerStore.searchFocusToken = newValue }
    }
    var inspectorListFocusToken: Int = 0
    var todoFocusToken: Int = 0
    /// Tracks the last intentional keyboard-driven focus target for ping-pong toggling.
    var lastFocusTarget: FocusTarget = .editor
    var explorerKeyboardFocusActive: Bool {
        get { explorerStore.isKeyboardFocusActive }
        set { explorerStore.isKeyboardFocusActive = newValue }
    }
    var exerciseKeyboardFocusActive: Bool = false
    var selectedExerciseListIndex: Int = 0
    var expandedExplorerDirectoryPaths: Set<String> {
        get { explorerStore.expandedDirectoryPaths }
        set { explorerStore.expandedDirectoryPaths = newValue }
    }
    var showLineNumbers: Bool = true
    var isCommandPalettePresented: Bool = false
    var commandPaletteSelectionDelta: Int = 0
    var goToLineTarget: Int? = nil
    var goToLineToken: Int = 0



    @ObservationIgnored private let importer: WorkspaceImporter
    @ObservationIgnored private let exercismAPIService = ExercismAPIService()
    @ObservationIgnored private let credentialStore = CredentialStore()

    @ObservationIgnored private let cargoRunner: CargoRunner
    @ObservationIgnored private let sourcePresentationBuilder: SourcePresentationBuilder
    @ObservationIgnored private let appPaths: AppStoragePaths
    @ObservationIgnored private let database: WorkspaceLibraryDatabase
    @ObservationIgnored private let repositoryCloner: RepositoryCloner
    @ObservationIgnored let exercismCLI: ExercismCLI
    @ObservationIgnored private let fileChangeService: WorkspaceFileChangeService
    @ObservationIgnored private let baselineStore: WorkspaceBaselineStore
    @ObservationIgnored private let rustlingsWorkspaceScaffolder: RustlingsWorkspaceScaffolder
    @ObservationIgnored private let todoScanner = TodoScanner()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isRestoringState = false
    @ObservationIgnored private var workspaceFileBaseline: [String: Data] = [:]
    @ObservationIgnored var draftEditorTextByPath: [String: String] {
        get { editorStore.draftTextByPath }
        set { editorStore.draftTextByPath = newValue }
    }
    @ObservationIgnored var chatStore: ChatStore?
    @ObservationIgnored let editorStore: EditorStateStore
    @ObservationIgnored let explorerStore: ExplorerStore

    init(
        appPaths: AppStoragePaths = .live(),
        importer: WorkspaceImporter = WorkspaceImporter(),
        cargoRunner: CargoRunner = CargoRunner(),
        sourcePresentationBuilder: SourcePresentationBuilder = SourcePresentationBuilder(),
        database: WorkspaceLibraryDatabase,
        editorStore: EditorStateStore,
        explorerStore: ExplorerStore,
        repositoryCloner: RepositoryCloner? = nil,
        exercismCLI: ExercismCLI? = nil,
        fileChangeService: WorkspaceFileChangeService = WorkspaceFileChangeService(),
        rustlingsWorkspaceScaffolder: RustlingsWorkspaceScaffolder = RustlingsWorkspaceScaffolder(),
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.appPaths = appPaths
        self.editorStore = editorStore
        self.explorerStore = explorerStore
        self.importer = importer
        self.cargoRunner = cargoRunner
        self.sourcePresentationBuilder = sourcePresentationBuilder
        
        self.database = database
        self.repositoryCloner = repositoryCloner ?? RepositoryCloner(cloneLibraryURL: appPaths.cloneLibraryURL)
        self.exercismCLI = exercismCLI ?? ExercismCLI()
        self.fileChangeService = fileChangeService
        self.baselineStore = WorkspaceBaselineStore(baselineLibraryURL: appPaths.baselineLibraryURL)
        self.rustlingsWorkspaceScaffolder = rustlingsWorkspaceScaffolder
        self.sessionLog = []

        // Migrate legacy comma-CSV storage to native string arrays on first launch
        let migrateSet: (String) -> Set<String> = { key in
            if let array = defaults.stringArray(forKey: key) {
                return Set(array)
            }
            // One-time migration from old comma-separated format
            let legacyCSV = defaults.string(forKey: key) ?? ""
            let migrated = Set(legacyCSV.split(separator: ",").map(String.init).filter { !$0.isEmpty })
            defaults.setValue(Array(migrated), forKey: key)
            // Initialize defaults migrations
            return migrated
        }

        restorePersistedLibrary()
    }

    func attachChatStore(_ chatStore: ChatStore) {
        self.chatStore = chatStore
        chatStore.syncSelection(using: self)
    }

    /// True only when the user has explicitly opened a file tab.
    /// Falls back to false even if a workspace is loaded with a default first exercise,
    /// so closing the last tab returns the editor to the "Editor Ready" empty state.
    var hasSelection: Bool {
        selectedExerciseID != nil && !currentOpenTabs.isEmpty
    }

/// True when the file currently displayed in the editor is being AI-enriched.
    /// Checks the active URL (exercise or solution file) against the enrichment set.
    var isCurrentExerciseEnriching: Bool {
        let activeURL = selectedExplorerFileURL ?? selectedExercise?.sourceURL
        guard let activeURL else { return false }
        return enrichingExercisePaths.contains(activeURL.standardizedFileURL.path)
    }

    /// True when any given URL (exercises or solutions) is in the enrichment set.
    func isEnriching(exerciseURL: URL) -> Bool {
        enrichingExercisePaths.contains(exerciseURL.standardizedFileURL.path)
    }






    var currentFileTree: [WorkspaceFileNode] {
        filteredFileTree(workspace?.fileTree ?? [])
    }

    var allWorkspaceFiles: [WorkspaceFileNode] {
        flattenToFiles(workspace?.fileTree ?? [])
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
        workspace?.title ?? AppBrand.shortName
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
        // No open tab → return default empty-state title
        guard hasSelection || isShowingExplorerPreview else { return "Ready to Code" }

        if let selectedExplorerFileURL, selectedExplorerFileURL != selectedExercise?.sourceURL {
            return selectedExplorerFileURL.lastPathComponent
        }

        return selectedExercise?.title ?? "Ready to Code"
    }

    var activeEditorSubtitle: String {
        // No open tab → return default subtitle
        guard hasSelection || isShowingExplorerPreview else {
            return "Import an exercise to begin editing."
        }

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
        # \(AppBrand.shortName)

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

    var isCodeCraftersWorkspace: Bool {
        currentWorkspaceRecord?.sourceKind == .codeCrafters
    }

    func submissionProvider(exercismStore: ExercismStore) -> (any ExerciseSubmissionProvider)? {
        guard let kind = currentWorkspaceRecord?.sourceKind else { return nil }
        switch kind {
        case .exercism:
            return ExercismSubmissionProvider(exercismStore: exercismStore)
        case .codeCrafters:
            return CodeCraftersSubmissionProvider()
        case .created, .imported, .cloned:
            return LocalCompletionProvider()
        }
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
        alert.informativeText = "Create a managed \(AppBrand.shortName) workspace for authoring custom Rustlings-style exercises."
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
        alert.informativeText = "Paste a Git repository URL. \(AppBrand.shortName) will clone it into the local workspace library and load it."
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




    func markExerciseCompleted(_ id: URL) {
        guard let idx = workspace?.exercises.firstIndex(where: { $0.id == id }) else { return }
        workspace?.exercises[idx].isMarkedDone = true
        persistCurrentWorkspaceSnapshot()
    }

    func importWorkspace(from url: URL, sourceKind: WorkspaceSourceKind = .imported, cloneURL: String? = nil) {
        if isEditorDirty {
            saveSelectedExercise()
        }

        do {
            var appliedSourceKind = sourceKind
            if sourceKind == .imported || sourceKind == .cloned {
                let codeCraftersDir = url.appendingPathComponent(".codecrafters", isDirectory: true)
                if FileManager.default.fileExists(atPath: codeCraftersDir.path) {
                    appliedSourceKind = .codeCrafters
                }
            }

            let managedWorkspace = try prepareWorkspaceForImport(from: url, sourceKind: appliedSourceKind)
            loadWorkspace(
                at: managedWorkspace.rootURL,
                sourceKind: appliedSourceKind,
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

    var commandPaletteInitialQuery: String = ""

    func showWorkspacePalette() {
        isWorkspacePickerPresented = true
        workspacePickerFocusToken &+= 1
    }

    func hideWorkspacePalette() {
        isWorkspacePickerPresented = false
    }

    func showCommandPalette(with query: String = "") {
        commandPaletteInitialQuery = query
        isCommandPalettePresented = true
    }

    func hideCommandPalette() {
        isCommandPalettePresented = false
    }

    func toggleLineNumbers() {
        showLineNumbers.toggle()
    }

    func goToLine(_ line: Int) {
        // Ensure the exercise file is open and focused before navigating
        if let exerciseURL = selectedExercise?.sourceURL {
            let isAlreadyOpen = currentOpenTabs.contains(where: {
                $0.url.standardizedFileURL == exerciseURL.standardizedFileURL
            })
            if !isAlreadyOpen {
                openExplorerFile(exerciseURL)
            } else {
                // If open but not active, activate it
                activateDocument(at: exerciseURL, persistState: true)
            }
        }

        // Small delay to ensure the text editor is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            goToLineTarget = line
            goToLineToken &+= 1
        }
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

        // Focus the text editor after opening
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.lastFocusTarget = .editor
            NotificationCenter.default.post(name: .focusTextEditorRequested, object: nil)
        }
    }

    func clearConsoleOutput() {
        consoleOutput = ""
    }

    func appendAISessionMessage(_ message: String) {
        appendSessionMessage("AI  \(message)")
    }

    func closeTab(_ tab: ActiveDocumentTab) {
        guard let closingIndex = openTabs.firstIndex(of: tab) else {
            return
        }

        // Never save during enrichment — editorText may be stale/empty while read-only
        let isFileEnriching = enrichingExercisePaths.contains(tab.url.standardizedFileURL.path)
        if isEditorDirty, !isFileEnriching,
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
        // Block saves while the file is being AI-enriched to prevent writing
        // stale/empty editorText over the stub or in-flight enrichment.
        if isCurrentExerciseEnriching { return }

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
            currentDiffText = ""
            appendSessionMessage("Saved \(selectedExercise.sourceURL.lastPathComponent)")
            persistCurrentWorkspaceSnapshot()
        } catch {
            consoleOutput += "Save failed: \(error.localizedDescription)\n"
            appendSessionMessage("Save failed for \(selectedExercise.sourceURL.lastPathComponent)")
        }
    }

    func runSelectedExercise(processStore: ProcessStore) {
        guard let selectedExercise else {
            return
        }

        saveSelectedExercise()

        Task {
            await processStore.performRun(exercise: selectedExercise, overrideCursorLine: nil, using: self)
        }
    }

    func runSelectedExerciseTests(processStore: ProcessStore) {
        guard let selectedExercise else {
            return
        }

        saveSelectedExercise()

        Task { @MainActor in
            guard let target = resolveSelectedExerciseTestTarget() else {
                appendSessionMessage("No test target found for \(selectedExercise.title)")
                consoleOutput += "No test target found for the current selection.\n"
                return
            }

            await processStore.performRun(exercise: target.exercise, overrideCursorLine: target.cursorLine, using: self)
        }
    }

    func resolveSelectedExerciseTestTarget() -> (exercise: ExerciseDocument, cursorLine: Int?)? {
        guard let selectedExercise else {
            return nil
        }

        if selectedExercise.fileRole == .tests {
            return (selectedExercise, nil)
        }

        if let testLine = findTestModuleLine(in: editorText) {
            return (selectedExercise, testLine)
        }

        guard let workspace else {
            return nil
        }

        let scopePath = selectedExercise.chatScopeURL.standardizedFileURL.path
        let integrationTests = workspace.exercises
            .filter {
                $0.fileRole == .tests &&
                $0.chatScopeURL.standardizedFileURL.path == scopePath
            }
            .sorted {
                $0.sourceURL.path.localizedCaseInsensitiveCompare($1.sourceURL.path) == .orderedAscending
            }

        guard !integrationTests.isEmpty else {
            return nil
        }

        let preferredNames = preferredIntegrationTestNames(for: selectedExercise)
        if let matched = integrationTests.first(where: { preferredNames.contains($0.sourceURL.deletingPathExtension().lastPathComponent.lowercased()) }) {
            return (matched, nil)
        }

        return (integrationTests[0], nil)
    }

    private func preferredIntegrationTestNames(for exercise: ExerciseDocument) -> Set<String> {
        var names: Set<String> = []
        names.insert(exercise.sourceURL.deletingPathExtension().lastPathComponent.lowercased())
        names.insert(exercise.chatScopeURL.deletingPathExtension().lastPathComponent.lowercased())

        let normalizedTitle = exercise.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        names.insert(normalizedTitle)

        return names
    }

    private func findTestModuleLine(in source: String) -> Int? {
        let lines = source.components(separatedBy: "\n")
        // First pass: look for #[cfg(test)] — the canonical test attribute
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#[cfg(test") {
                return index + 1 // 1-based
            }
        }
        // Second pass: look for mod tests / mod test
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("mod tests") || trimmed.hasPrefix("mod test ") || trimmed == "mod test{" {
                return index + 1
            }
        }
        return nil
    }
    func toggleProblemPaneVisibility() {
        persistCurrentWorkspaceSnapshot()
    }


    func selectRightSidebarTab(_ tab: RightSidebarTab) {

        guard rightSidebarTab != tab else {
            persistCurrentWorkspaceSnapshot()
            return
        }

        rightSidebarTab = tab
        persistCurrentWorkspaceSnapshot()
    }

    func setRightSidebarWidth(_ width: CGFloat) {
        let fixedWidth = CrabTimeTheme.Layout.inspectorWidth
        _ = width
        guard abs(rightSidebarWidth - fixedWidth) > 0.5 else {
            return
        }

        rightSidebarWidth = fixedWidth
        persistCurrentWorkspaceSnapshot()
    }

    func focusChatComposer() {
        if lastFocusTarget == .chat {
            // Ping-pong: was on chat → return to editor
            lastFocusTarget = .editor
            NotificationCenter.default.post(name: .focusTextEditorRequested, object: nil)
        } else {
            lastFocusTarget = .chat
            selectRightSidebarTab(.chat)
            chatComposerFocusToken += 1
        }
        persistCurrentWorkspaceSnapshot()
    }

    func focusInspectorSidebar() {
        // cmd+shift+i is now wired to focusInspectorList; keep this as a direct open
        selectRightSidebarTab(.inspector)
    }






    func jumpToTestCheck(_ check: ExerciseCheck) {
        guard let workspace else { return }
        let testName = check.id

        // Determine where tests might live by scanning .rs files in root
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: workspace.rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        // Find testing macro (e.g., #[test], #[tokio::test])
        // Note: compiled once as a static property — not per call.

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "rs", !fileURL.path.contains("/target/") else { continue }
            if fileURL.lastPathComponent.hasPrefix(".rustgoblin-") { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            guard content.contains(testName) else { continue }

            let lines = content.components(separatedBy: .newlines)
            var pendingMacroLines: [Int] = []

            for (index, rawLine) in lines.enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("#[") {
                    pendingMacroLines.append(index)
                    continue
                }

                let isFn = line.hasPrefix("fn ") || line.hasPrefix("async fn ") || line.hasPrefix("pub fn ") || line.hasPrefix("pub async fn ")
                
                guard isFn else {
                    if !line.isEmpty { pendingMacroLines.removeAll() }
                    continue
                }

                defer { pendingMacroLines.removeAll() }

                let nameMatches = line.contains("fn \(testName)(") || line.contains("fn \(testName)<") || line.contains("fn \(testName) ")
                guard nameMatches else { continue }

                // Is it marked with a testing macro?
                let isTest = pendingMacroLines.contains { macroIndex in
                    let attr = lines[macroIndex].trimmingCharacters(in: .whitespaces)
                    let nsRange = NSRange(attr.startIndex..<attr.endIndex, in: attr)
                    return Self.testMacroRegex.firstMatch(in: attr, options: [], range: nsRange) != nil
                }

                if isTest {
                    let macroIndexToJump = pendingMacroLines.first ?? index
                    
                    activateDocument(at: fileURL, persistState: true)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.lastFocusTarget = .editor
                        NotificationCenter.default.post(name: .focusTextEditorRequested, object: nil)
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.goToLine(macroIndexToJump + 1)
                    }
                    return
                }
            }
        }
    }









    func toggleLeftColumnVisibility() {
        toggleProblemPaneVisibility()
    }

    /// Toggles keyboard focus between a named target and the text editor (ping-pong pattern).
    /// First press activates the target; second press returns focus to the editor.
    private func toggleFocus(to target: FocusTarget, onActivate: () -> Void) {
        if lastFocusTarget == target {
            lastFocusTarget = .editor
            explorerKeyboardFocusActive = false
            NotificationCenter.default.post(name: .focusTextEditorRequested, object: nil)
        } else {
            lastFocusTarget = target
            explorerKeyboardFocusActive = false
            onActivate()
        }
        persistCurrentWorkspaceSnapshot()
    }

    func showExplorerAndFocusSearch() {
        toggleFocus(to: .explorerSearch) { explorerSearchFocusToken += 1 }
    }

    func showExerciseLibraryAndFocusSearch() {
        toggleFocus(to: .exerciseSearch) { exerciseSearchFocusToken += 1 }
    }

    func showExercismCatalogAndFocusSearch() {
        toggleFocus(to: .exercismSearch) { exercismSearchFocusToken += 1 }
    }

    func showTodoAndFocus() {
        toggleFocus(to: .todo) {
            todoFocusToken += 1
        }
    }

    func focusInspectorList() {
        if lastFocusTarget == .inspectorList {
            lastFocusTarget = .editor
            let savedOffset = editorCursorOffset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(
                    name: .restoreCursorPositionRequested,
                    object: nil,
                    userInfo: ["offset": savedOffset]
                )
            }
        } else {
            lastFocusTarget = .inspectorList
            rightSidebarTab = .inspector
            inspectorListFocusToken += 1
            // Resign text editor so the InspectorKeyBridge global monitor
            // can capture j/k/arrows/enter without them typing into the file.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow)
            }
        }
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

    func handleChatSlashCommand(_ input: String) async throws -> ChatSlashCommandResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return nil
        }

        let components = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let command = components.first?.lowercased() ?? trimmed.lowercased()
        let argument = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch command {
        case "/challenge":
            return .localReply(try await createWorkspaceChallenge(named: argument))
        case "/verify":
            return try await verifySelectedExercise()
        case "/try-again":
            return .localReply(try await retryEnrichChallenge(argument: argument))
        default:
            throw ChatCommandError.unknownCommand(command)
        }
    }

    private func verifySelectedExercise() async throws -> ChatSlashCommandResult {
        guard let exercise = selectedExercise else {
            return .localReply("No exercise selected to verify.")
        }
        
        let target = resolveSelectedExerciseTestTarget()
        let runExercise = target?.exercise ?? exercise
        let runCursorLine = target?.cursorLine

        // Save editor contents so we compile the latest code
        await MainActor.run {
            saveSelectedExercise()
        }

        let output = try await cargoRunner.run(exercise: runExercise, cursorLine: runCursorLine)
        
        let sourceCode = (try? String(contentsOf: exercise.sourceURL, encoding: .utf8)) ?? ""
        var solutionCode = ""
        
        if let workspace = workspace {
            let sourcePath = exercise.sourceURL.standardizedFileURL.path
            let rootPath = workspace.rootURL.standardizedFileURL.path
            if sourcePath.hasPrefix(rootPath + "/exercises/") {
                let relPath = String(sourcePath.dropFirst((rootPath + "/exercises/").count))
                let solutionURL = workspace.rootURL
                    .appendingPathComponent("solutions")
                    .appendingPathComponent(relPath)
                if let code = try? String(contentsOf: solutionURL, encoding: .utf8) {
                    solutionCode = code
                }
            }
            // Note: /verify no longer auto-marks done. Only "Verify & Mark Done" (AI-confirmed) does.
        }
        
        let prompt = """
        I ran `/verify` on my solution.

        ### Terminal Output
        ```text
        \(output.stdout)\(output.stderr.isEmpty ? "" : "\n" + output.stderr)
        ```

        ### My Code (\(exercise.sourceURL.lastPathComponent))
        ```rust
        \(sourceCode)
        ```
        \(solutionCode.isEmpty ? "" : "\n### Reference Solution\n```rust\n\(solutionCode)\n```")

        Please verify my code. If there are compiler errors or the terminal output shows test failures or panics, explain what went wrong and how I can fix it. Be very beginner-friendly.
        If the code ran successfully, compare it with the solution/requirements and tell me if it correctly fulfills the objective. If it's correct, confirm and praise my work!
        """
        
        return .rewritePrompt(prompt)
    }

    func applyCargoRunnerOverride(args: String) async {
        guard let workspaceURL = workspace?.rootURL ?? selectedExercise?.directoryURL else { return }
        let splitArgs = args.components(separatedBy: " ").filter { !$0.isEmpty }
        
        
        do {
            let output = try await cargoRunner.runOverride(args: splitArgs, in: workspaceURL)
            appendSessionMessage("Override applied: \(args)")
            if !output.stdout.isEmpty {
                consoleOutput += output.stdout
                if !consoleOutput.hasSuffix("\n") { consoleOutput += "\n" }
            }
            if !output.stderr.isEmpty {
                consoleOutput += output.stderr
                if !consoleOutput.hasSuffix("\n") { consoleOutput += "\n" }
            }
        } catch {
            consoleOutput += "Override failed: \(error.localizedDescription)\n"
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

    /// Select the exercise and open its file in the editor with focus.
    func selectAndOpenExercise(id: ExerciseDocument.ID) {
        selectExercise(id: id)
        guard let exercise = workspace?.exercises.first(where: { $0.id == id }) else {
            return
        }
        openExplorerFile(exercise.sourceURL)
    }

    /// Open the first visible exercise from the search results.
    func openFirstVisibleExercise() {
        guard let first = visibleExercises.first else {
            return
        }
        selectAndOpenExercise(id: first.id)
    }

    func persistExplorerSearchTextChange() {
        explorerKeyboardFocusActive = false
        selectFirstVisibleExplorerEntry()
    }

    func setExerciseKeyboardFocus(active: Bool) {
        exerciseKeyboardFocusActive = active
    }

    func moveExerciseSelectionUp() {
        selectedExerciseListIndex = max(selectedExerciseListIndex - 1, 0)
    }

    func moveExerciseSelectionDown() {
        let count = visibleExercises.count
        guard count > 0 else { return }
        selectedExerciseListIndex = min(selectedExerciseListIndex + 1, count - 1)
    }

    func openSelectedExerciseListIndex() {
        let items = visibleExercises
        guard items.indices.contains(selectedExerciseListIndex) else { return }
        selectAndOpenExercise(id: items[selectedExerciseListIndex].id)
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



    func openSolutionFile() {
        guard let solutionURL = selectedExercise?.solutionURL,
              FileManager.default.fileExists(atPath: solutionURL.path) else {
            return
        }

        activateDocument(at: solutionURL, persistState: true)
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
            This will permanently delete the managed workspace files for “\(record.title)” and remove all related Crab Time data.

            This action is destructive.
            """
        } else {
            message = """
            This workspace lives outside Crab Time managed storage. Crab Time will remove it from the library and delete its saved data, but it will leave the original files on disk untouched.

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
        Task {
            await prepareDiffForActiveDocument()
        }
    }

    func toggleProblemMaximize() {
    }

    func toggleEditorMaximize() {
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

            workspace = loadedWorkspace

            if refreshBaseline {
                do {
                    try baselineStore.captureBaseline(from: loadedWorkspace.rootURL)
                } catch {
                    appendSessionMessage("Baseline snapshot skipped: \(error.localizedDescription)")
                }
            }

            workspaceFileBaseline = baselineStore.loadBaselineData(for: loadedWorkspace)
            if workspaceFileBaseline.isEmpty {
                workspaceFileBaseline = snapshotWorkspaceFiles(for: loadedWorkspace)
            }
            draftEditorTextByPath = [:]
            selectedWorkspaceRootPath = rootPath
            isSolutionVisible = false
            currentDiffText = ""
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
        rightSidebarTab = state.rightSidebarTab
        rightSidebarWidth = CrabTimeTheme.Layout.inspectorWidth
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

    func activateDocument(at url: URL, persistState: Bool) {
        guard let workspace else {
            return
        }

        // Save cursor position of the file we're leaving
        saveCursorPositionForCurrentFile()

        captureDraftForActiveEditableDocument()
        selectedExplorerFileURL = url.standardizedFileURL
        selectedExplorerNodePath = url.standardizedFileURL.path
        registerOpenTab(url)
        currentDiffText = ""

        if let matchingExercise = workspace.exercises.first(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            selectedExerciseID = matchingExercise.id
            let sourcePath = matchingExercise.sourceURL.standardizedFileURL.path

            // During enrichment, always read fresh from disk — the in-memory model may be stale
            if enrichingExercisePaths.contains(sourcePath),
               let diskContent = try? String(contentsOf: url, encoding: .utf8) {
                editorText = diskContent
                isEditorDirty = false
            } else {
                editorText = draftEditorTextByPath[sourcePath] ?? matchingExercise.presentation.visibleSource
                isEditorDirty = draftEditorTextByPath[sourcePath] != nil
            }
            explorerPreviewText = ""
            selectedChatSessionID = nil
        } else {
            // Non-exercise files (solutions, Cargo.toml, etc.) — always read from disk
            explorerPreviewText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            isEditorDirty = false
        }

        chatStore?.syncSelection(using: self)

        // Schedule cursor restoration for the newly activated file
        let targetPath = url.standardizedFileURL.path
        if let savedOffset = cursorPositionByPath[targetPath] {
            restoreCursorOffset = savedOffset
        } else {
            restoreCursorOffset = nil
        }
        restoreCursorToken &+= 1

        if persistState {
            persistCurrentWorkspaceSnapshot()
        }
    }

    /// Save the current text editor's cursor position keyed by active file path.
    func saveCursorPositionForCurrentFile() {
        guard let currentURL = selectedExplorerFileURL else { return }
        NotificationCenter.default.post(
            name: .saveCursorPositionRequested,
            object: nil,
            userInfo: ["path": currentURL.standardizedFileURL.path]
        )
    }

    /// Called from the text editor coordinator when cursor position is captured.
    func setCursorPosition(offset: Int, forPath path: String) {
        cursorPositionByPath[path] = offset
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
        selectedExerciseID = nil
        selectedExplorerFileURL = nil
        selectedExplorerNodePath = nil
        explorerPreviewText = ""
        openTabs = []
        editorText = ""
        currentDiffText = ""
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

        // Never store an empty string as a draft — it would blank the editor on reopen
        if editorText.isEmpty || editorText == baseText {
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
        } catch {
            currentDiffText = "Diff failed: \(error.localizedDescription)"
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
            exercise.isMarkedDone = progress.isMarkedDone
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

    func persistCurrentWorkspaceSnapshot() {
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
                sidebarMode: .exercises,
                isInspectorVisible: true,
                rightSidebarTab: rightSidebarTab,
                rightSidebarWidth: rightSidebarWidth,
                terminalDisplayMode: .split,
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
                    checkStatuses: Dictionary(uniqueKeysWithValues: exercise.checks.map { ($0.id, $0.status) }),
                    isMarkedDone: exercise.isMarkedDone
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

    var isCurrentExerciseCompleted: Bool {
        guard let exercise = selectedExercise, let workspace = workspace else { return false }
        return isExerciseCompleted(exercise, in: workspace)
    }

    private func isExerciseCompleted(_ exercise: ExerciseDocument, in workspace: ExerciseWorkspace? = nil) -> Bool {
        // Only an explicit "Mark as Done" (AI-verified) counts as completed.
        // Passing test checks alone do NOT move an exercise to the Done tab.
        return exercise.isMarkedDone
    }

    func applyCheckResults(from result: ProcessOutput) {
        guard
            var workspaceLocal = workspace,
            let selectedExerciseID = selectedExerciseID,
            let selectedIndex = workspaceLocal.exercises.firstIndex(where: { $0.id == selectedExerciseID })
        else {
            return
        }

        let existingChecks = workspaceLocal.exercises[selectedIndex].checks
        let combinedOutput = [result.stdout, result.stderr].joined(separator: "\n")
        let lowerOutput = combinedOutput.lowercased()

        // Detect if this was a test run by looking for test runner output markers
        let isTestRun = lowerOutput.contains("running") && lowerOutput.contains("test")
            || lowerOutput.contains("test result:")
            || lowerOutput.contains("... ok")
            || lowerOutput.contains("... failed")

        var updatedChecks = existingChecks

        if isTestRun {
            // Dynamically discover and update tests parsed from cargo runner standard output
            // Example: `test test_name ... ok`
            let regex = try? NSRegularExpression(pattern: "test\\s+([a-zA-Z0-9_]+)\\s+\\.{3}\\s+(ok|failed|ignored|passed)", options: [])
            if let regex = regex {
                let nsString = combinedOutput as NSString
                let matches = regex.matches(in: combinedOutput, options: [], range: NSRange(location: 0, length: nsString.length))
                
                for match in matches {
                    guard match.numberOfRanges == 3 else { continue }
                    let id = nsString.substring(with: match.range(at: 1))
                    let statusText = nsString.substring(with: match.range(at: 2)).lowercased()
                    
                    let status: CheckStatus
                    if statusText == "ok" || statusText == "passed" {
                        status = .passed
                    } else if statusText == "failed" {
                        status = .failed
                    } else {
                        status = .idle // ignored
                    }
                    
                    if let existingIndex = updatedChecks.firstIndex(where: { $0.id == id }) {
                        updatedChecks[existingIndex].status = status
                    } else {
                        // Dynamically register the non-AST bounds test
                        let newCheck = ExerciseCheck(id: id, title: id, detail: "Integration Test", symbolName: "testtube.2", status: status)
                        updatedChecks.append(newCheck)
                    }
                }
            }
        }

        workspaceLocal.exercises[selectedIndex].checks = updatedChecks.map { check in
            var check = check

            if check.id == "manual-run" {
                check.status = result.terminationStatus == 0 ? .passed : .failed
                return check
            }

            // The dynamic parsing above handled test updates safely!
            return check
        }
        
        self.workspace = workspaceLocal
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

    private func flattenToFiles(_ nodes: [WorkspaceFileNode]) -> [WorkspaceFileNode] {
        var files: [WorkspaceFileNode] = []
        for node in nodes {
            if node.isDirectory {
                files.append(contentsOf: flattenToFiles(node.children))
            } else {
                files.append(node)
            }
        }
        return files
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
        let isFiltering = !explorerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isFiltering {
            // When filtering, select the first file that matches, not a directory
            if let firstFile = entries.first(where: { !$0.node.isDirectory }) {
                selectedExplorerNodePath = firstFile.path
                return
            }
        }
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

        if appPaths.containsManagedWorkspace(originRootURL) || sourceKind == .cloned || sourceKind == .exercism {
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
        case .imported, .codeCrafters:
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

    private func retryEnrichChallenge(argument rawArgument: String) async throws -> String {
        guard let workspace, let record = currentWorkspaceRecord else {
            throw NSError(
                domain: "WorkspaceStore", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Open a workspace before using `/try-again`."]
            )
        }

        // Strip leading @ and whitespace to get the relative path
        var relPath = rawArgument
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if relPath.hasPrefix("@") { relPath = String(relPath.dropFirst()) }
        relPath = relPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !relPath.isEmpty else {
            throw NSError(
                domain: "WorkspaceStore", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Usage: `/try-again @exercises/lifetimes.rs`"]
            )
        }

        let exerciseURL = workspace.rootURL.appendingPathComponent(relPath).standardizedFileURL

        // Derive the solution URL by swapping exercises/ → solutions/
        let solutionRelPath = relPath.replacingOccurrences(of: "exercises/", with: "solutions/")
        let solutionURL = workspace.rootURL.appendingPathComponent(solutionRelPath).standardizedFileURL

        guard FileManager.default.fileExists(atPath: exerciseURL.path) else {
            throw NSError(
                domain: "WorkspaceStore", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "File not found: \(relPath). Use @ to pick a file from the workspace."]
            )
        }

        // Build a ChallengeResult from the resolved paths
        let slugComponents = exerciseURL.deletingPathExtension().lastPathComponent
        let title = slugComponents
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
        let result = RustlingsWorkspaceScaffolder.ChallengeResult(
            title: title,
            slug: slugComponents,
            workspaceRootURL: workspace.rootURL,
            exerciseURL: exerciseURL,
            solutionURL: solutionURL,
            devUpdateMessage: nil
        )

        let providerManager = chatStore?.providerManager
        enrichingExercisePaths.insert(exerciseURL.standardizedFileURL.path)
        enrichingExercisePaths.insert(solutionURL.standardizedFileURL.path)

        rustlingsWorkspaceScaffolder.enrichChallengeInBackground(
            result: result,
            providerManager: providerManager,
            onLog: { [weak self] msg in self?.appendSessionMessage(msg) },
            onComplete: { [weak self] exerciseURL, solutionURL, message in
                guard let self else { return }
                self.enrichingExercisePaths.remove(exerciseURL.standardizedFileURL.path)
                self.enrichingExercisePaths.remove(solutionURL.standardizedFileURL.path)
                self.reloadDocumentState(afterExternalChangeAt: exerciseURL)
                self.reloadDocumentState(afterExternalChangeAt: solutionURL)
                if let data = try? Data(contentsOf: exerciseURL) {
                    self.workspaceFileBaseline[exerciseURL.standardizedFileURL.path] = data
                }
                if let data = try? Data(contentsOf: solutionURL) {
                    self.workspaceFileBaseline[solutionURL.standardizedFileURL.path] = data
                }
                self.appendSessionMessage(message)
            }
        )

        return "🔄 Re-enriching **\(slugComponents)** with AI in background.\n\n- Exercise: `\(relPath)`\n- Solution: `\(solutionRelPath)`\n\n_The session log will update when enrichment completes._"
    }

    // MARK: - AI-Verified Mark as Done

    enum VerificationError: LocalizedError {
        case noExercise
        case compilationFailed(String)
        case notCorrect(String)
        case aiUnavailable

        var errorDescription: String? {
            switch self {
            case .noExercise:
                return "No exercise is currently selected."
            case .compilationFailed(let feedback):
                return "Code did not compile or run successfully.\n\n\(feedback)"
            case .notCorrect(let feedback):
                return feedback
            case .aiUnavailable:
                return "An AI provider is required to verify completion. Configure one in Settings."
            }
        }
    }

    /// Runs the selected exercise, asks the AI to evaluate correctness with a strict PASS/FAIL
    /// response, and marks the exercise done only if the AI returns PASS.
    func verifyAndMarkDone(for exerciseID: URL) async throws -> SubmissionResult {
        guard let exercise = workspace?.exercises.first(where: { $0.id == exerciseID }) else {
            throw VerificationError.noExercise
        }

        guard let providerManager = chatStore?.providerManager else {
            appendSessionMessage("⚠️ No AI provider configured — cannot verify completion.")
            throw VerificationError.aiUnavailable
        }

        // Save editor so we compile the latest buffer
        saveSelectedExercise()

        let target = resolveSelectedExerciseTestTarget()
        let runExercise = target?.exercise ?? exercise
        let runCursorLine = target?.cursorLine

        appendSessionMessage("🔍 Verifying \(exercise.title)…")

        let output = try await cargoRunner.run(exercise: runExercise, cursorLine: runCursorLine)

        // Compilation / runtime failure → do not even ask AI
        if output.terminationStatus != 0 {
            let feedback = [output.stdout, output.stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            appendSessionMessage("❌ \(exercise.title): code did not compile or run.\n\n```\n\(feedback)\n```")
            throw VerificationError.compilationFailed(feedback)
        }

        // Load source + solution for the AI evaluation
        let sourceCode = (try? String(contentsOf: exercise.sourceURL, encoding: .utf8)) ?? ""
        var solutionCode = ""
        if let workspace = workspace {
            let srcPath = exercise.sourceURL.standardizedFileURL.path
            let rootPath = workspace.rootURL.standardizedFileURL.path
            if srcPath.hasPrefix(rootPath + "/exercises/") {
                let rel = String(srcPath.dropFirst((rootPath + "/exercises/").count))
                let solURL = workspace.rootURL.appendingPathComponent("solutions").appendingPathComponent(rel)
                solutionCode = (try? String(contentsOf: solURL, encoding: .utf8)) ?? ""
            }
        }

        let terminalOutput = [output.stdout, output.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let solutionBlock = solutionCode.isEmpty ? "" : """

Reference solution:
```rust
\(solutionCode)
```
"""

        let systemPrompt = """
You are a strict Rust exercise evaluator. The student's code compiled and ran successfully. \
Determine if it CORRECTLY fulfills the exercise objective.

CRITICAL RULES:
- If the code contains `todo!()` macros, immediately return FAIL.
- If the code does not meaningfully implement the logic described in the comments or demonstrated by the solution, return FAIL.
- If the code is correct and complete, return PASS.

Respond with EXACTLY ONE of:
- "PASS" — the code genuinely implements the objective.
- "FAIL: [one-sentence reason]" — the code does not genuinely implement the objective.

Do NOT add anything else. Do NOT explain. Do NOT teach.
"""
        let userMessage = """
Exercise: \(exercise.title)

Student code (\(exercise.sourceURL.lastPathComponent)):
```rust
\(sourceCode)
```
\(solutionBlock)

Terminal output:
```
\(terminalOutput)
```
"""

        appendSessionMessage("🤖 Asking AI to evaluate \(exercise.title)…")

        // Strict 60s timeout for the evaluation call
        let aiTask = Task {
            try await providerManager.generate(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                workspaceRootPath: workspace?.rootURL.path ?? ""
            )
        }
        let timerTask = Task.detached {
            try? await Task.sleep(for: .seconds(60))
            aiTask.cancel()
        }

        let rawResponse: String
        do {
            rawResponse = try await aiTask.value
            timerTask.cancel()
        } catch is CancellationError {
            timerTask.cancel()
            appendSessionMessage("⏱ AI evaluation timed out for \(exercise.title).")
            throw VerificationError.aiUnavailable
        } catch {
            timerTask.cancel()
            appendSessionMessage("⚠️ AI error during evaluation: \(error.localizedDescription)")
            throw VerificationError.aiUnavailable
        }

        let verdict = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        if verdict.uppercased().hasPrefix("PASS") {
            markExerciseCompleted(exerciseID)
            appendSessionMessage("✅ AI verified — **\(exercise.title)** is marked done!")
            return .markedDone
        } else {
            // Extract the FAIL reason (after "FAIL: ")
            let reason: String
            if let colonIdx = verdict.firstIndex(of: ":") {
                reason = String(verdict[verdict.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                reason = verdict
            }
            let feedback = "**\(exercise.title)** is not yet complete.\n\n\(reason)"
            appendSessionMessage("🔴 \(feedback)")
            throw VerificationError.notCorrect(feedback)
        }
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

        let startedAt = Date()

        // Phase 1: Write stub files instantly — no AI, no waiting
        let result = try rustlingsWorkspaceScaffolder.createChallengeStub(
            named: trimmedName,
            in: workspace.rootURL
        )

        // Reload workspace immediately so exercise appears in the UI
        loadWorkspace(
            at: workspace.rootURL,
            sourceKind: record.sourceKind,
            cloneURL: record.cloneURL,
            originPath: record.originPath,
            restoreState: false,
            refreshBaseline: true
        )

        guard self.workspace != nil else {
            throw NSError(
                domain: "WorkspaceStore",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The exercise was created on disk but the workspace failed to reload."]
            )
        }

        if let createdExercise = self.workspace?.exercises.first(where: {
            $0.sourceURL.standardizedFileURL == result.exerciseURL.standardizedFileURL
        }) {
            applySelection(for: createdExercise.id)
            registerOpenTab(createdExercise.sourceURL)
            activateDocument(at: createdExercise.sourceURL, persistState: true)
        }

        let stubElapsed = Int(Date().timeIntervalSince(startedAt))
        appendSessionMessage("⚙️ Stub created in \(stubElapsed)s — AI enriching content in background…")

        // Phase 2: Fire AI enrichment in background — lock both exercise + solution
        let providerManager = chatStore?.providerManager
        enrichingExercisePaths.insert(result.exerciseURL.standardizedFileURL.path)
        enrichingExercisePaths.insert(result.solutionURL.standardizedFileURL.path)
        rustlingsWorkspaceScaffolder.enrichChallengeInBackground(
            result: result,
            providerManager: providerManager,
            onLog: { [weak self] msg in self?.appendSessionMessage(msg) },
            onComplete: { [weak self] exerciseURL, solutionURL, message in
                guard let self else { return }
                self.enrichingExercisePaths.remove(exerciseURL.standardizedFileURL.path)
                self.enrichingExercisePaths.remove(solutionURL.standardizedFileURL.path)

                // Reload in-memory model from disk so enriched content becomes the baseline.
                // This prevents false "unsaved" state and makes revert use enriched content.
                self.reloadDocumentState(afterExternalChangeAt: exerciseURL)
                self.reloadDocumentState(afterExternalChangeAt: solutionURL)

                // Update baselines so "revert" goes back to enriched content, not stub
                if let data = try? Data(contentsOf: exerciseURL) {
                    self.workspaceFileBaseline[exerciseURL.standardizedFileURL.path] = data
                }
                if let data = try? Data(contentsOf: solutionURL) {
                    self.workspaceFileBaseline[solutionURL.standardizedFileURL.path] = data
                }

                self.appendSessionMessage(message)
            }
        )

        let summaryLines = [
            "✅ Created `\(result.slug)` in **\(stubElapsed)s** — AI is enriching content in the background.",
            "",
            "- Exercise: `\(relativePath(for: result.exerciseURL, rootURL: workspace.rootURL))`",
            "- Solution: `\(relativePath(for: result.solutionURL, rootURL: workspace.rootURL))`",
            "- Updated: `info.toml`",
            "",
            "_You can start editing the stub now. The session log will update when AI enrichment is done._"
        ]

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
                    userInfo: [NSLocalizedDescriptionKey: "\(AppBrand.shortName) has no original baseline or recovery source for this workspace."]
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

            Crab Time will reuse your current Exercism setup instead of rewriting it automatically.
            """
        }

        guard let workspaceURL = status.workspaceURL else {
            return """
            Exercism CLI is installed, but no workspace is configured.

            Configure it with:
            exercism configure --workspace=\"$HOME/Exercism\" --token=YOUR_TOKEN

            Crab Time will import exercises from the configured Exercism workspace.
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

        Crab Time will download Exercism exercises into that workspace and then import them into the app library.
        """
    }

    private func promptLabel(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
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

    func appendSessionMessage(_ message: String) {
        sessionLog.insert(
            "\(Date().formatted(date: .omitted, time: .shortened))  \(message)",
            at: 0
        )
        if sessionLog.count > 4000 {
            sessionLog.removeLast(sessionLog.count - 4000)
        }
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

private struct ExplorerVisibleEntry {
    let node: WorkspaceFileNode
    let depth: Int
    let parentPath: String?

    var path: String {
        node.url.standardizedFileURL.path
    }
}

// Restore toggleTerminalVisibility
extension WorkspaceStore {
}

// MARK: - Static helpers

extension WorkspaceStore {
    /// Matches Rust testing attribute macros, e.g. `#[test]`, `#[tokio::test]`.
    /// Compiled once at class load time rather than inside the file-enumeration loop.
    static let testMacroRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"^\s*#\[.*test.*\]\s*$"#, options: [])
    }()
}

// MARK: - Typed errors

enum ChatCommandError: LocalizedError {
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let cmd):
            "Unknown command `\(cmd)`. Supported: `/challenge <name>`, `/verify`."
        }
    }
}
