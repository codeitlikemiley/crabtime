import Foundation

struct WorkspaceSessionState: Equatable, Codable, Sendable {
    let workspaceRootPath: String
    var selectedExercisePath: String?
    var activeTabPath: String?
    var openTabs: [ActiveDocumentTab]
    var sidebarMode: SidebarMode
    var searchQuery: String
    var difficultyFilter: ExerciseDifficulty?
    var completionFilter: ExerciseCompletionFilter
}
