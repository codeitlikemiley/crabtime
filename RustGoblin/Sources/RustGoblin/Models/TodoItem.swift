import Foundation

struct TodoItem: Identifiable, Equatable, Sendable {
    let id: String
    let filePath: String
    let fileName: String
    let line: Int
    let column: Int
    let text: String
    let kind: Kind

    enum Kind: String, CaseIterable, Sendable {
        case todoMacro = "todo!()"
        case todoComment = "// TODO"
        case todoDocComment = "/// TODO"
        case unimplemented = "unimplemented!()"
        case fixme = "FIXME"

        var icon: String {
            switch self {
            case .todoMacro: return "exclamationmark.circle"
            case .todoComment: return "text.badge.checkmark"
            case .todoDocComment: return "doc.text"
            case .unimplemented: return "questionmark.circle"
            case .fixme: return "wrench"
            }
        }

        var label: String {
            rawValue
        }
    }
}
