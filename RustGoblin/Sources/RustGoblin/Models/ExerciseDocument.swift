import Foundation

struct ExerciseDocument: Identifiable, Equatable, Sendable {
    let id: URL
    let title: String
    let summary: String
    let difficulty: ExerciseDifficulty
    let sortOrder: Int?
    let directoryURL: URL
    let sourceURL: URL
    let readmeURL: URL?
    let hintURL: URL?
    let solutionURL: URL?
    var readmeContent: String
    var hintContent: String
    var sourceCode: String
    var solutionCode: String?
    var presentation: SourcePresentation
    var checks: [ExerciseCheck]
    let fileNames: [String]
}
