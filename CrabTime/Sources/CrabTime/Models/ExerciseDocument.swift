import Foundation

struct ExerciseDocument: Identifiable, Equatable, Sendable {
    let id: URL
    let title: String
    let summary: String
    let difficulty: ExerciseDifficulty
    let fileRole: ExerciseFileRole
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

    var chatScopeURL: URL {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL

        if fileRole == .tests {
            return standardizedDirectoryURL.deletingLastPathComponent().standardizedFileURL
        }

        if standardizedDirectoryURL.lastPathComponent == "src" {
            let parentURL = standardizedDirectoryURL.deletingLastPathComponent().standardizedFileURL
            let cargoURL = parentURL.appendingPathComponent("Cargo.toml")
            if FileManager.default.fileExists(atPath: cargoURL.path) {
                return parentURL
            }
        }

        return standardizedDirectoryURL
    }
}
