import Foundation

struct AIProviderReply: Sendable {
    let content: String
    let backendSessionID: String?
    let didRecoverStaleSession: Bool

    init(
        content: String,
        backendSessionID: String? = nil,
        didRecoverStaleSession: Bool = false
    ) {
        self.content = content
        self.backendSessionID = backendSessionID
        self.didRecoverStaleSession = didRecoverStaleSession
    }
}
