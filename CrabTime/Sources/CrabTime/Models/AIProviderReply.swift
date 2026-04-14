import Foundation

struct AIProviderReply: Sendable {
    let content: String
    let thinkingContent: String?
    let backendSessionID: String?
    let didRecoverStaleSession: Bool

    init(
        content: String,
        thinkingContent: String? = nil,
        backendSessionID: String? = nil,
        didRecoverStaleSession: Bool = false
    ) {
        self.content = content
        self.thinkingContent = thinkingContent
        self.backendSessionID = backendSessionID
        self.didRecoverStaleSession = didRecoverStaleSession
    }
}
