import Foundation

struct ExerciseChatSession: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let workspaceRootPath: String
    let exercisePath: String
    var title: String
    var providerKind: AIProviderKind
    var model: String
    var backendSessionID: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workspaceRootPath: String,
        exercisePath: String,
        title: String,
        providerKind: AIProviderKind,
        model: String,
        backendSessionID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceRootPath = workspaceRootPath
        self.exercisePath = exercisePath
        self.title = title
        self.providerKind = providerKind
        self.model = model
        self.backendSessionID = backendSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
