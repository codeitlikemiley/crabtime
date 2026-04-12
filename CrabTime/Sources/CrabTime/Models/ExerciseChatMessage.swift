import Foundation

enum ExerciseChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case error
}

enum ExerciseChatMessageStatus: String, Codable, Sendable {
    case complete
    case streaming
    case failed
}

struct ExerciseChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID
    let role: ExerciseChatRole
    var content: String
    let createdAt: Date
    var status: ExerciseChatMessageStatus
    var metadataJSON: String?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        role: ExerciseChatRole,
        content: String,
        createdAt: Date = Date(),
        status: ExerciseChatMessageStatus = .complete,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
        self.metadataJSON = metadataJSON
    }
}
