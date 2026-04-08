import Foundation

enum CheckStatus: String, Codable, Sendable {
    case idle
    case passed
    case failed
}
