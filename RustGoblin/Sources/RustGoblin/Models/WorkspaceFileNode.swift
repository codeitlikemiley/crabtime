import Foundation

struct WorkspaceFileNode: Identifiable, Equatable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let children: [WorkspaceFileNode]
}
