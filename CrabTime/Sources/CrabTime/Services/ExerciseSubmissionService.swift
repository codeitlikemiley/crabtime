import Foundation
import Observation

@Observable
@MainActor
final class ExerciseSubmissionService {
    var isSubmitting: Bool = false
    var lastSubmissionResult: SubmissionResult?
    /// AI FAIL reason from verifyAndMarkDone — shown directly in the Inspector below the button.
    var verificationFeedback: String? = nil

    var submissionFeedbackURL: URL? {
        if case .submitted(let url) = lastSubmissionResult {
            return url
        }
        return nil
    }

    init() {}

    func submit(using store: WorkspaceStore, processStore: ProcessStore, exercismStore: ExercismStore) {
        guard let provider = store.submissionProvider(exercismStore: exercismStore) else {
            store.consoleOutput += "Submission failed: unknown workspace source kind.\n"
            return
        }

        guard provider.canSubmit(store: store) else {
            return
        }

        // Clear any previous AI feedback on each new attempt
        verificationFeedback = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }

            do {
                let result = try await provider.submit(store: store, processStore: processStore)
                self.lastSubmissionResult = result
                self.verificationFeedback = nil  // clear on success

            } catch let verErr as WorkspaceStore.VerificationError {
                // Verification errors are already logged to the session by verifyAndMarkDone.
                // Surface the human-readable reason directly in the Inspector.
                switch verErr {
                case .notCorrect(let feedback):
                    self.verificationFeedback = feedback
                case .compilationFailed:
                    self.verificationFeedback = "Build failed — fix compilation errors first."
                case .aiUnavailable:
                    self.verificationFeedback = "AI provider required to verify completion. Check Settings → AI."
                case .noExercise:
                    self.verificationFeedback = "No exercise is currently selected."
                }
                self.lastSubmissionResult = .skipped(reason: verErr.errorDescription ?? "Verification failed.")

            } catch {
                // Non-verification errors — original handling
                store.consoleOutput += "Submit error: \(error.localizedDescription)\n"
                var errorMsg = error.localizedDescription
                if let cliError = error as? CodeCraftersCLI.CLIError, case .submitFailed(let message) = cliError {
                    errorMsg = message
                } else if let cliError = error as? ExercismCLI.CLIError, case .submitFailed(let message) = cliError {
                    errorMsg = message
                }

                let stripped = errorMsg.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ": ")
                    .replacingOccurrences(of: "Error: ", with: "")

                let maxLen = 65
                let truncated = stripped.count > maxLen ? "\(stripped.prefix(maxLen))..." : stripped
                store.appendSessionMessage("Submit failed: \(truncated)")

                self.lastSubmissionResult = .skipped(reason: errorMsg)
            }
        }
    }
}
