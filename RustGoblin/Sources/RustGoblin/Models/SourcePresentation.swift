import Foundation

struct SourcePresentation: Equatable, Sendable {
    let prefix: String
    let visibleSource: String
    let suffix: String
    let hiddenChecks: [ExerciseCheck]

    func rebuild(with visibleSource: String) -> String {
        prefix + visibleSource + suffix
    }
}
