import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class ProcessStore {

    // AI runtime properties
    var aiRuntimeProviderTitle: String = "No AI activity yet"
    var aiRuntimeModel: String = ""
    var aiRuntimeTransport: AITransportKind?
    var aiRuntimeSessionID: String?
    var aiRuntimeProcessStatus: String = "Idle"
    var aiRuntimeAuthStatus: String = "Idle"
    var aiRuntimeLogPath: String?
    var aiRuntimeLastEvent: String?
    var aiRuntimeLastError: String?
    var aiRuntimeEvents: [String] = []
    var aiRuntimeToolCalls: [AIToolCallSnapshot] = []

    var diagnostics: [Diagnostic] = []
    
    var diagnosticsCount: Int {
        diagnostics.count
    }
    var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }
    var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }
    var selectedDiagnosticIndex: Int = 0

    var runState: RunState = .idle
    var lastCommandDescription: String = ""
    var lastTerminationStatus: Int32?
    var isSubmittingExercism: Bool = false

    @ObservationIgnored let cargoRunner: CargoRunner

    init(cargoRunner: CargoRunner = CargoRunner()) {
        self.cargoRunner = cargoRunner
    }

    func appendAIRuntimeEvent(_ message: String) {
        let stamped = "\(Date().formatted(date: .omitted, time: .shortened))  \(message)"
        aiRuntimeLastEvent = stamped
        aiRuntimeEvents.insert(stamped, at: 0)
        if aiRuntimeEvents.count > 200 {
            aiRuntimeEvents.removeLast(aiRuntimeEvents.count - 200)
        }
    }

    func updateAIToolCall(id: String, title: String, status: String) {
        if let index = aiRuntimeToolCalls.firstIndex(where: { $0.id == id }) {
            aiRuntimeToolCalls[index].title = title
            aiRuntimeToolCalls[index].status = status
            aiRuntimeToolCalls[index].updatedAt = Date()
            return
        }

        aiRuntimeToolCalls.insert(
            AIToolCallSnapshot(id: id, title: title, status: status, updatedAt: Date()),
            at: 0
        )
        if aiRuntimeToolCalls.count > 40 {
            aiRuntimeToolCalls.removeLast(aiRuntimeToolCalls.count - 40)
        }
    }

    func handleAITransportEvent(_ event: AITransportEvent) {
        switch event {
        case .transportSelected(let provider, let transport, let model):
            aiRuntimeEvents = []
            aiRuntimeToolCalls = []
            aiRuntimeProviderTitle = provider.title
            aiRuntimeTransport = transport
            aiRuntimeModel = model
            aiRuntimeSessionID = nil
            aiRuntimeProcessStatus = transport == .acp ? "Launching" : "Not applicable"
            aiRuntimeAuthStatus = transport == .acp ? "Waiting" : "Not applicable"
            aiRuntimeLogPath = nil
            aiRuntimeLastEvent = nil
            aiRuntimeLastError = nil
            appendAIRuntimeEvent("\(provider.shortTitle) using \(transport.title) with \(model)")
        case .processState(let provider, let status, let logFilePath):
            aiRuntimeProviderTitle = provider.title
            aiRuntimeProcessStatus = status
            aiRuntimeLogPath = logFilePath ?? aiRuntimeLogPath
            appendAIRuntimeEvent(status)
        case .sessionReady(let provider, _, let sessionID, let reused, let logFilePath):
            aiRuntimeProviderTitle = provider.title
            aiRuntimeSessionID = sessionID
            aiRuntimeProcessStatus = "Connected"
            aiRuntimeAuthStatus = "Ready"
            aiRuntimeLogPath = logFilePath
            appendAIRuntimeEvent(reused ? "Reused ACP session \(sessionID)" : "Created ACP session \(sessionID)")
        case .authState(let provider, let status):
            aiRuntimeProviderTitle = provider.title
            aiRuntimeAuthStatus = status
            appendAIRuntimeEvent(status)
        case .transportError(let provider, let message, let logFilePath):
            aiRuntimeProviderTitle = provider.title
            aiRuntimeProcessStatus = "Failed"
            aiRuntimeLastError = message
            aiRuntimeLogPath = logFilePath ?? aiRuntimeLogPath
            appendAIRuntimeEvent("Error: \(message)")
        case .toolCall(let provider, let id, let title, let status):
            aiRuntimeProviderTitle = provider.title
            updateAIToolCall(id: id, title: title, status: status)
            appendAIRuntimeEvent("Tool \(title) [\(status)]")
        case .note(let provider, let message):
            aiRuntimeProviderTitle = provider.title
            appendAIRuntimeEvent(message)
        }
    }

    func aiRuntimeBannerMessage(for provider: AIProviderKind, transport: AITransportKind) -> String? {
        guard transport == .acp, aiRuntimeProviderTitle == provider.title else {
            return nil
        }

        if let aiRuntimeLastError, !aiRuntimeLastError.isEmpty {
            return "ACP unavailable. Open AI Runtime."
        }
        if aiRuntimeAuthStatus.localizedCaseInsensitiveContains("fail") {
            return "ACP auth failed. Open AI Runtime."
        }
        if aiRuntimeAuthStatus.localizedCaseInsensitiveContains("authenticating") {
            return "ACP authenticating…"
        }
        if let aiRuntimeLastEvent, aiRuntimeLastEvent.localizedCaseInsensitiveContains("invalid") {
            return "Stale session recovered. Open AI Runtime."
        }
        if aiRuntimeSessionID != nil {
            return "ACP healthy. Session warm."
        }
        return "ACP enabled. First send will cold start."
    }

    func showAIRuntime(using store: WorkspaceStore) {
        store.selectConsoleTab(.aiRuntime)
    }

    func reconnectCurrentAITransport(using store: WorkspaceStore) {
        guard aiRuntimeTransport == .acp else { return }
        store.chatStore?.reconnectSelectedACP(using: store)
    }

    func resetCurrentWarmAISession(using store: WorkspaceStore) {
        guard aiRuntimeTransport == .acp else { return }
        aiRuntimeSessionID = nil
        aiRuntimeToolCalls = []
        aiRuntimeLastError = nil
        aiRuntimeProcessStatus = "Idle"
        store.chatStore?.resetSelectedWarmSession(using: store)
    }

    func openAIRuntimeLogs() {
        guard let aiRuntimeLogPath else {
            return
        }
        let url = URL(fileURLWithPath: aiRuntimeLogPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    func performRun(exercise targetExercise: ExerciseDocument? = nil, overrideCursorLine: Int? = nil, using store: WorkspaceStore) async {
        guard let exercise = targetExercise ?? store.selectedExercise else {
            return
        }

        runState = .running
        store.selectedConsoleTab = .output
        lastCommandDescription = ""
        store.consoleOutput += "\n[\(Date().formatted(date: .omitted, time: .standard))] Running \(exercise.title)…\n"
        store.appendSessionMessage("Started \(exercise.title)")

        do {
            let cursorLine = targetExercise == nil ? (overrideCursorLine ?? store.editorCursorLine) : overrideCursorLine
            let result = try await cargoRunner.run(exercise: exercise, cursorLine: cursorLine)
            lastCommandDescription = result.commandDescription
            lastTerminationStatus = result.terminationStatus
            diagnostics = DiagnosticParser.parse(result.stderr)
            store.applyCheckResults(from: result)

            store.appendSessionMessage("$ \(result.commandDescription)")

            if !result.stdout.isEmpty {
                store.consoleOutput += result.stdout
            }

            if !result.stderr.isEmpty {
                store.consoleOutput += result.stderr
            }

            runState = result.terminationStatus == 0 ? .succeeded : .failed

            store.appendSessionMessage(
                "Finished \(exercise.title) with status \(result.terminationStatus)"
            )
            store.persistCurrentWorkspaceSnapshot()
        } catch {
            runState = .failed
            store.consoleOutput += "Run failed: \(error.localizedDescription)\n"
            store.appendSessionMessage("Run failed for \(exercise.title)")
            store.persistCurrentWorkspaceSnapshot()
        }
    }

    func performBackgroundCheck(projectRootURL: URL, using store: WorkspaceStore) async {
        store.appendSessionMessage("Running background check…")

        do {
            let result = try await cargoRunner.check(projectRootURL: projectRootURL)

            guard result.commandDescription != "no check available" else {
                return
            }

            store.appendSessionMessage("$ \(result.commandDescription)")

            let combinedOutput = [result.stdout, result.stderr].joined(separator: "\n")
            diagnostics = DiagnosticParser.parse(combinedOutput)

            let errorCount = diagnostics.filter { $0.severity == .error }.count
            let warningCount = diagnostics.filter { $0.severity == .warning }.count

            if result.terminationStatus != 0 || errorCount > 0 || warningCount > 0 {
                if errorCount > 0 || warningCount > 0 {
                    store.appendSessionMessage("Check: \(errorCount) error(s), \(warningCount) warning(s)")
                } else {
                    let trimmedOutput = combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedOutput.isEmpty {
                        store.appendSessionMessage("Check output:\n\(trimmedOutput)")
                    }
                }
                store.selectedConsoleTab = .diagnostics
            } else {
                store.appendSessionMessage("Check: clean ✓")
            }
        } catch {
            store.appendSessionMessage("Background check failed: \(error.localizedDescription)")
        }
    }

    func moveDiagnosticSelectionUp() {
        guard !diagnostics.isEmpty else { return }
        selectedDiagnosticIndex = max(selectedDiagnosticIndex - 1, 0)
    }

    func moveDiagnosticSelectionDown() {
        guard !diagnostics.isEmpty else { return }
        selectedDiagnosticIndex = min(selectedDiagnosticIndex + 1, diagnostics.count - 1)
    }

    func activateSelectedDiagnostic(using store: WorkspaceStore) {
        guard diagnostics.indices.contains(selectedDiagnosticIndex) else { return }
        if let line = diagnostics[selectedDiagnosticIndex].line {
            store.goToLine(line)
        }
    }
}
