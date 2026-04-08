import Foundation

enum WorkspaceSourceKind: String, Codable, Sendable {
    case imported
    case cloned
    case exercism
}

struct SavedWorkspaceRecord: Identifiable, Equatable, Codable, Sendable {
    let rootPath: String
    var title: String
    var sourceKind: WorkspaceSourceKind
    var cloneURL: String?
    var addedAt: Date
    var lastOpenedAt: Date
    var isMissing: Bool

    var id: String { rootPath }

    var rootURL: URL {
        URL(fileURLWithPath: rootPath)
    }

    var displayTitle: String {
        isMissing ? "\(title) (Missing)" : title
    }
}
