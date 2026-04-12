import Foundation

struct ExerciseWorkspace: Equatable, Sendable {
    let rootURL: URL
    let title: String
    var exercises: [ExerciseDocument]
    let fileTree: [WorkspaceFileNode]
}
