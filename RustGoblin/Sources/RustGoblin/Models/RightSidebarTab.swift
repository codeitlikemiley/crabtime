import Foundation

enum RightSidebarTab: String, CaseIterable, Codable, Sendable {
    case inspector
    case chat

    var title: String {
        switch self {
        case .inspector:
            "Inspector"
        case .chat:
            "Chat"
        }
    }

    var systemImage: String {
        switch self {
        case .inspector:
            "sidebar.right"
        case .chat:
            "bubble.left.and.bubble.right"
        }
    }
}
