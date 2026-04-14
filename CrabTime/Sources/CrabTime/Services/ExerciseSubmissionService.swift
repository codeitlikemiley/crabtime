import Foundation
import Observation

@Observable
@MainActor
final class ExerciseSubmissionService {
    var isSubmitting: Bool = false
    var lastSubmissionResult: SubmissionResult?
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
        
        isSubmitting = true
        
        Task {
            defer { isSubmitting = false }
            
            do {
                let result = try await provider.submit(store: store, processStore: processStore)
                self.lastSubmissionResult = result
            } catch {
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
