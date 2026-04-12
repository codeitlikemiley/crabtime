import Foundation

struct ExerciseCheck: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbolName: String
    var status: CheckStatus = .idle
    var line: Int? = nil
}
