import Foundation

enum RunState: String, Codable, Sendable {
    case idle
    case running
    case succeeded
    case failed
}
