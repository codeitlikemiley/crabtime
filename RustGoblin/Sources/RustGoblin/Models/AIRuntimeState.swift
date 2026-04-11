import Foundation

struct AIToolCallSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var status: String
    var updatedAt: Date
}

enum AITransportEvent: Sendable {
    case transportSelected(provider: AIProviderKind, transport: AITransportKind, model: String)
    case processState(provider: AIProviderKind, status: String, logFilePath: String?)
    case sessionReady(provider: AIProviderKind, transport: AITransportKind, sessionID: String, reused: Bool, logFilePath: String?)
    case authState(provider: AIProviderKind, status: String)
    case transportError(provider: AIProviderKind, message: String, logFilePath: String?)
    case toolCall(provider: AIProviderKind, id: String, title: String, status: String)
    case note(provider: AIProviderKind, message: String)
}
