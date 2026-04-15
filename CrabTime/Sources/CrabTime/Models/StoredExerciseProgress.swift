import Foundation

struct StoredExerciseProgress: Equatable, Codable, Sendable {
    let workspaceRootPath: String
    let exercisePath: String
    var difficulty: ExerciseDifficulty
    var passedCheckCount: Int
    var totalCheckCount: Int
    var lastRunStatus: RunState
    var lastOpenedAt: Date
    var checkStatuses: [String: CheckStatus]
    var isMarkedDone: Bool = false
}
