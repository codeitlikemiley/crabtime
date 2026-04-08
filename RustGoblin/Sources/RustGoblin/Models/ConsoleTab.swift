import Foundation

enum ConsoleTab: String, CaseIterable, Identifiable, Sendable {
    case output = "Output"
    case diagnostics = "Diagnostics"
    case session = "Session"

    var id: String { rawValue }
}
