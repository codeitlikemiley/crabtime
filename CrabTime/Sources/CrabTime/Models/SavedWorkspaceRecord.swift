import Foundation

enum WorkspaceSourceKind: String, Codable, Sendable {
    case imported
    case cloned
    case exercism
    case created
}

struct SavedWorkspaceRecord: Identifiable, Equatable, Codable, Sendable {
    let rootPath: String
    var title: String
    var sourceKind: WorkspaceSourceKind
    var cloneURL: String?
    var originPath: String?
    var addedAt: Date
    var lastOpenedAt: Date
    var isMissing: Bool

    var id: String { rootPath }

    var rootURL: URL {
        URL(fileURLWithPath: rootPath)
    }

    var originURL: URL? {
        originPath.map { URL(fileURLWithPath: $0) }
    }

    var displayTitle: String {
        isMissing ? "\(title) (Missing)" : title
    }
}
