import Foundation

struct WorkspaceSessionState: Equatable, Codable, Sendable {
    let workspaceRootPath: String
    var selectedExercisePath: String?
    var activeTabPath: String?
    var openTabs: [ActiveDocumentTab]
    var sidebarMode: SidebarMode
    var isInspectorVisible: Bool
    var rightSidebarTab: RightSidebarTab
    var rightSidebarWidth: Double
    var terminalDisplayMode: TerminalDisplayMode
    var searchQuery: String
    var difficultyFilter: ExerciseDifficulty?
    var showsOnlyTestExercises: Bool
    var completionFilter: ExerciseCompletionFilter
    var selectedChatSessionID: UUID?
}
