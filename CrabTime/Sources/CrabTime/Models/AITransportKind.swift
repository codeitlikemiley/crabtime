import Foundation

enum AITransportKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case legacyCLI
    case acp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .legacyCLI:
            "Current CLI"
        case .acp:
            "ACP"
        }
    }

    var summary: String {
        switch self {
        case .legacyCLI:
            "Starts a fresh CLI process for each chat turn."
        case .acp:
            "Keeps a warm ACP session alive after the first startup."
        }
    }
}
