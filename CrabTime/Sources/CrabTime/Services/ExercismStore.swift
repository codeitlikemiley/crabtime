import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class ExercismStore {
    var exercismExercises: [ExercismExercise] = []
    var exercismSearchText: String = ""
    var exercismFilters: Set<String> = []
    var isDownloadingExercism: Bool = false
    var isSubmittingExercism: Bool = false
    var isLoadingExercismExercises: Bool = false
    var selectedExercismIndex: Int = 0
    private(set) var exercismDownloadedExercises: Set<String> = []
    private(set) var exercismCompletedExercises: Set<String> = []

    @ObservationIgnored private let exercismCLI: ExercismCLI
    @ObservationIgnored private let credentialStore: CredentialStore
    @ObservationIgnored private let defaults: UserDefaults

    init(exercismCLI: ExercismCLI = ExercismCLI(), credentialStore: CredentialStore = CredentialStore(), defaults: UserDefaults = .standard) {
        self.exercismCLI = exercismCLI
        self.credentialStore = credentialStore
        self.defaults = defaults

        self.exercismDownloadedExercises = Set((defaults.string(forKey: "exercismDownloadedExercises") ?? "").split(separator: ",").map(String.init))
        self.exercismCompletedExercises = Set((defaults.string(forKey: "exercismCompletedExercises") ?? "").split(separator: ",").map(String.init))
    }

    func markExercismDownloaded(_ slug: String) {
        exercismDownloadedExercises.insert(slug)
        defaults.set(exercismDownloadedExercises.joined(separator: ","), forKey: "exercismDownloadedExercises")
    }

    func markExercismCompleted(_ slug: String) {
        exercismCompletedExercises.insert(slug)
        defaults.set(exercismCompletedExercises.joined(separator: ","), forKey: "exercismCompletedExercises")
    }

    func canSubmitSelectedExerciseToExercism(using store: WorkspaceStore) -> Bool {
        store.isExercismWorkspace && !isSubmittingExercism
    }

    func submitSelectedExerciseToExercism(using store: WorkspaceStore, processStore: ProcessStore) {
        guard let selectedExercise = store.selectedExercise,
              canSubmitSelectedExerciseToExercism(using: store) else {
            return
        }

        store.saveSelectedExercise()
        let modifiedFiles = store.modifiedWorkspaceRelativePaths

        guard !modifiedFiles.isEmpty else {
            store.consoleOutput += "Exercism submit skipped: no modified files to submit.\n"
            store.appendSessionMessage("Skipped Exercism submit for \(selectedExercise.title)")
            return
        }

        Task {
            await performExercismSubmit(for: selectedExercise, files: modifiedFiles, using: store, processStore: processStore)
        }
    }

    private func performExercismSubmit(for exercise: ExerciseDocument, files: [String], using store: WorkspaceStore, processStore: ProcessStore) async {
        guard store.isExercismWorkspace, let workspace = store.workspace else {
            return
        }

        isSubmittingExercism = true
        store.consoleOutput += "\n[\(Date().formatted(date: .omitted, time: .standard))] Submitting \(exercise.title) to Exercism…\n"
        store.appendSessionMessage("Submitting \(exercise.title) to Exercism")

        defer {
            isSubmittingExercism = false
        }

        do {
            let exerciseDirectoryURL: URL = {
                if let originURL = store.currentWorkspaceRecord?.originURL {
                    return originURL
                }

                if let cliStatus = try? store.exercismCLI.status(), let cliWorkspaceURL = cliStatus.workspaceURL {
                    var rawSlug = workspace.rootURL.lastPathComponent
                    if let range = rawSlug.range(of: #"-[0-9a-f]{8}$"#, options: .regularExpression) {
                        rawSlug = String(rawSlug[rawSlug.startIndex..<range.lowerBound])
                    }
                    let candidateURL = cliWorkspaceURL
                        .appendingPathComponent("rust", isDirectory: true)
                        .appendingPathComponent(rawSlug, isDirectory: true)
                    if FileManager.default.fileExists(atPath: candidateURL.path) {
                        return candidateURL
                    }
                }

                return workspace.rootURL
            }()

            let result = try await store.exercismCLI.submit(
                exerciseDirectoryURL: exerciseDirectoryURL,
                files: files
            )
            processStore.lastCommandDescription = result.commandDescription
            processStore.lastTerminationStatus = result.terminationStatus

            if !result.stdout.isEmpty {
                store.consoleOutput += result.stdout
                if !result.stdout.hasSuffix("\n") {
                    store.consoleOutput += "\n"
                }
            }

            if !result.stderr.isEmpty {
                store.consoleOutput += result.stderr
                if !result.stderr.hasSuffix("\n") {
                    store.consoleOutput += "\n"
                }
            }

            await MainActor.run {
                self.markExercismCompleted(workspace.rootURL.lastPathComponent)
            }

            store.appendSessionMessage("Submitted \(exercise.title) to Exercism")
        } catch {
            store.consoleOutput += "Exercism submit failed: \(error.localizedDescription)\n"
            if let cliError = error as? ExercismCLI.CLIError, case .submitFailed(let message) = cliError {
                let stripped = message.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ": ")
                    .replacingOccurrences(of: "Error: ", with: "")
                
                let maxLen = 65
                let truncated = stripped.count > maxLen ? "\(stripped.prefix(maxLen))..." : stripped
                store.appendSessionMessage("Submit failed: \(truncated)")
            } else {
                store.appendSessionMessage("Exercism submit failed for \(exercise.title)")
            }
        }
    }

    var visibleExercismExercises: [ExercismExercise] {
        var items = exercismExercises
        
        if !exercismFilters.isEmpty {
            let selectedDifficulties = exercismFilters.filter { ["easy", "medium", "hard"].contains($0) }
            let needsDownloaded = exercismFilters.contains("downloaded")
            let needsCompleted = exercismFilters.contains("completed")
            
            if !selectedDifficulties.isEmpty {
                items = items.filter { selectedDifficulties.contains($0.difficulty) }
            }
            if needsDownloaded {
                items = items.filter { exercismDownloadedExercises.contains($0.slug) }
            }
            if needsCompleted {
                items = items.filter { exercismCompletedExercises.contains($0.slug) }
            }
        }
        
        if !exercismSearchText.isEmpty {
            let search = exercismSearchText.lowercased()
            items = items.filter {
                $0.title.lowercased().contains(search) ||
                $0.blurb.lowercased().contains(search) ||
                $0.slug.lowercased().contains(search)
            }
        }
        
        return items
    }

    func fetchExercismCatalog() async {
        guard let token = credentialStore.readSecret(for: "exercism_api_token"), !token.isEmpty else { return }
        guard exercismExercises.isEmpty else { return }

        isLoadingExercismExercises = true
        defer { isLoadingExercismExercises = false }

        do {
            let apiService = ExercismAPIService()
            let exercises = try await apiService.fetchRustExercises(token: token)
            exercismExercises = exercises
        } catch {
            print("Failed to fetch Exercism exercises: \(error.localizedDescription)")
        }
    }

    func moveExercismSelectionUp() {
        guard !visibleExercismExercises.isEmpty else { return }
        selectedExercismIndex = max(selectedExercismIndex - 1, 0)
    }

    func moveExercismSelectionDown() {
        guard !visibleExercismExercises.isEmpty else { return }
        selectedExercismIndex = min(selectedExercismIndex + 1, visibleExercismExercises.count - 1)
    }

    func activateSelectedExercismExercise(using store: WorkspaceStore, processStore: ProcessStore) {
        let items = visibleExercismExercises
        guard items.indices.contains(selectedExercismIndex) else { return }
        downloadExercismExercise(slug: items[selectedExercismIndex].slug, using: store, processStore: processStore)
    }

    func downloadExercismExercise(slug: String, using store: WorkspaceStore, processStore: ProcessStore) {
        downloadExercismExercise(track: "rust", exercise: slug, using: store, processStore: processStore)
    }

    func downloadExercismExercise(track expectedTrack: String, exercise expectedExercise: String, using store: WorkspaceStore, processStore: ProcessStore) {
        Task {

            guard let status = try? exercismCLI.status(), status.isInstalled, status.hasToken, let _ = status.workspaceURL else {
                showExercismStatus()
                return
            }

            var requestedTrack = expectedTrack
            var requestedExercise = expectedExercise

            if expectedTrack.isEmpty || expectedExercise.isEmpty {
                let initialPrompt = expectedTrack.isEmpty ? "" : "exercism download --track=\(expectedTrack) --exercise="
                do {
                    let parts = try resolveExercismDownloadInput(
                        command: PromptValue.shared.command,
                        track: expectedTrack,
                        exercise: expectedExercise
                    )
                    requestedTrack = parts.track
                    requestedExercise = parts.exercise
                } catch {
                    showBlockingAlert(
                        title: "Invalid Input",
                        message: "Please provide either a valid target link, or explicitly enter the track and exercise name.",
                        style: .warning
                    )
                    PromptValue.shared.command = ""
                    return
                }
            }

            store.appendSessionMessage("Downloading Exercism exercise '\(requestedExercise)'...")

            do {
                let destinationURL = try await exercismCLI.download(track: requestedTrack, exercise: requestedExercise)
                markExercismDownloaded(requestedExercise)
                store.appendSessionMessage("Downloaded to \(destinationURL.path)")
                store.importWorkspace(from: destinationURL, sourceKind: .exercism, cloneURL: nil)
            } catch {
                store.consoleOutput += "Exercism download failed: \(error.localizedDescription)\n"
                showBlockingAlert(
                    title: "Download Failed",
                    message: "Failed to download \(requestedTrack)/\(requestedExercise).\n\n\(error.localizedDescription)",
                    style: .critical
                )
                PromptValue.shared.command = ""
            }
        }
    }

    func showExercismStatus() {
        Task {
            if let status = try? exercismCLI.status() {
                showBlockingAlert(
                    title: "Exercism Diagnosis",
                    message: exercismStatusMessage(for: status),
                    style: .informational
                )
            } else {
                showBlockingAlert(
                    title: "Exercism Diagnosis",
                    message: "Failed to load Exercism status.",
                    style: .warning
                )
            }
        }
    }

    func showExercismDownloadPrompt(using store: WorkspaceStore, processStore: ProcessStore) {
        let alert = NSAlert()
        alert.messageText = "Download Exercism Exercise"
        alert.informativeText = "Paste the download command from Exercism (or just the link/slug if the track is rust)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Check Status")

        let inputTextField = PromptTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = PromptValue.shared.command
        inputTextField.placeholderString = "exercism download --track=rust --exercise=..."

        alert.accessoryView = inputTextField
        alert.window.initialFirstResponder = inputTextField

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            PromptValue.shared.command = inputTextField.stringValue
            downloadExercismExercise(track: "", exercise: "", using: store, processStore: processStore)
        case .alertThirdButtonReturn:
            PromptValue.shared.command = inputTextField.stringValue
            showExercismStatus()
        default:
            PromptValue.shared.command = inputTextField.stringValue
        }
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
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// Global struct to persist between showExercismDownloadPrompt closes
@MainActor
private class PromptValue {
    static let shared = PromptValue()
    var command: String = ""
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
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.window?.makeFirstResponder(self)
                self.currentEditor()?.selectedRange = NSRange(location: 0, length: self.stringValue.count)
            }
        }
    }
}

enum PromptValidationError: Error, LocalizedError {
    case missingTrackOrExercise
    case invalidExercismCommand

    var errorDescription: String? {
        switch self {
        case .missingTrackOrExercise:
            return "Both track and exercise slug must be specified."
        case .invalidExercismCommand:
            return "Unable to parse --track and --exercise from the provided command."
        }
    }
}
