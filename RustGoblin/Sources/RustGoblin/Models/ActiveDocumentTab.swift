import Foundation

struct ActiveDocumentTab: Identifiable, Equatable, Codable, Sendable {
    let path: String

    var id: String { path }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var title: String {
        url.lastPathComponent
    }

    init(url: URL) {
        self.path = url.standardizedFileURL.path
    }
}
