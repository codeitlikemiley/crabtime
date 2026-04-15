import Foundation
import Observation

/// The result of an exercise submission attempt.
enum SubmissionResult {
    /// Submission was successful on a remote server, optionally returning a feedback URL.
    case submitted(url: URL?)
    /// Exercise was marked done locally directly.
    case markedDone
    /// Submission was skipped (for example, no files changed).
    case skipped(reason: String)
}

/// A provider that encapsulates how an exercise is submitted or marked completed.
@MainActor
protocol ExerciseSubmissionProvider: Sendable {
    /// The text to display on the primary submit button.
    var actionLabel: String { get }
    /// An SF Symbol name used when showing the submit button as an icon.
    var actionIcon: String { get }
    /// Indicates whether calling `submit(...)` involves remote networking and should show a progress state.
    var supportsRemoteSubmit: Bool { get }
    
    /// Determines whether the provider is currently allowed to submit.
    func canSubmit(store: WorkspaceStore) -> Bool
    
    /// Submits the currently selected exercise (or marks it done), returning the result.
    func submit(store: WorkspaceStore, processStore: ProcessStore) async throws -> SubmissionResult
}

// MARK: - Local Completion Provider

/// Provides local-only completion tracking (like completing a custom Rustlings exercise).
/// Clicking "Verify & Mark Done" compiles the code, runs it, and asks the AI for a
/// PASS/FAIL verdict before marking the exercise as done.
struct LocalCompletionProvider: ExerciseSubmissionProvider {
    var actionLabel: String { "Verify & Mark Done" }
    var actionIcon: String { "checkmark.seal" }
    var supportsRemoteSubmit: Bool { false }
    
    func canSubmit(store: WorkspaceStore) -> Bool {
        store.hasSelection && !store.isCurrentExerciseCompleted
    }
    
    func submit(store: WorkspaceStore, processStore: ProcessStore) async throws -> SubmissionResult {
        guard let exercise = store.selectedExercise else {
            return .skipped(reason: "No active exercise")
        }
        
        // Compile + AI evaluation → marks done only if AI returns PASS
        return try await store.verifyAndMarkDone(for: exercise.id)
    }
}

// MARK: - Exercism Provider

/// Encapsulates Exercism-specific submission logic via ExercismStore.
struct ExercismSubmissionProvider: ExerciseSubmissionProvider {
    let exercismStore: ExercismStore
    
    var actionLabel: String { "Submit to Exercism" }
    var actionIcon: String { "paperplane.fill" }
    var supportsRemoteSubmit: Bool { true }
    
    func canSubmit(store: WorkspaceStore) -> Bool {
        exercismStore.canSubmitSelectedExerciseToExercism(using: store)
    }
    
    func submit(store: WorkspaceStore, processStore: ProcessStore) async throws -> SubmissionResult {
        // As a temporary bridge, we call the existing store method.
        // In a full refactor, the logic from ExercismStore.performExercismSubmit would live here.
        // For now, we simulate the async wait and return a generic success.
        exercismStore.submitSelectedExerciseToExercism(using: store, processStore: processStore)
        
        // Wait while it sets the flag
        try await Task.sleep(nanoseconds: 100_000_000)
        while exercismStore.isSubmittingExercism {
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        
        // Let's assume it succeeded if it finished attempting and the slug is in completed.
        // This avoids duplicating logic before fully decommissioning the ExercismStore method.
        var slug = store.workspace?.rootURL.lastPathComponent ?? ""
        if let range = slug.range(of: #"-([0-9a-f]{8})$"#, options: .regularExpression) {
            slug.removeSubrange(range)
        }
        
        if exercismStore.exercismCompletedExercises.contains(slug) {
            let feedbackURL = URL(string: "https://exercism.org/tracks/rust/exercises/\(slug)")
            return .submitted(url: feedbackURL)
        } else {
            return .skipped(reason: "Submit may have failed or no files changed.")
        }
    }
}

// MARK: - CodeCrafters Provider

struct CodeCraftersSubmissionProvider: ExerciseSubmissionProvider {
    let cli: CodeCraftersCLI = CodeCraftersCLI()
    
    var actionLabel: String { "Submit to CodeCrafters" }
    var actionIcon: String { "hammer.fill" }
    var supportsRemoteSubmit: Bool { true }
    
    func canSubmit(store: WorkspaceStore) -> Bool {
        // isRunning is now owned exclusively by ProcessStore;
        // the run button is guarded separately so double-submit protection is unnecessary here.
        store.hasSelection
    }
    
    func submit(store: WorkspaceStore, processStore: ProcessStore) async throws -> SubmissionResult {
        guard let workspace = store.workspace else {
            return .skipped(reason: "No workspace active")
        }
        
        if store.isEditorDirty {
            store.saveSelectedExercise()
        }
        
        store.consoleOutput += "\n[CodeCrafters] Submitting to CodeCrafters server...\n"
        store.appendSessionMessage("Submitting to CodeCrafters")
        
        // Execute the submit command wrapped in a 30s timeout locally just in case
        let submitTask = Task { () -> ProcessOutput in
            try await cli.submit(workspaceDirectoryURL: workspace.rootURL)
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 45_000_000_000) // 45 seconds max wait for remote tests
            submitTask.cancel()
        }
        
        do {
            let result = try await submitTask.value
            timeoutTask.cancel()
            
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
            
            let feedbackURL = CodeCraftersCLI.parseFeedbackURL(from: result.combinedText)
            
            if result.terminationStatus == 0 {
                if let exercise = store.selectedExercise {
                    store.markExerciseCompleted(exercise.id)
                }
                store.appendSessionMessage("CodeCrafters tests passed!")
                return .submitted(url: feedbackURL)
            } else {
                store.appendSessionMessage("CodeCrafters tests failed.")
                // It's still a "submission", just didn't pass the tests yet.
                // We don't mark as done, but maybe we could return .submitted(url: feedbackURL) so they can view logs?
                // Let's throw error so UI knows it failed
                throw CodeCraftersCLI.CLIError.submitFailed(message: "Tests failed or submission error.")
            }
            
        } catch is CancellationError {
            store.consoleOutput += "[CodeCrafters] Submission timed out after 45s.\n"
            throw CodeCraftersCLI.CLIError.submitFailed(message: "Timed out.")
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }
}
