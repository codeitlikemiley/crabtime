import Foundation

struct AppStoragePaths: Equatable, Sendable {
    let baseURL: URL

    var databaseURL: URL {
        baseURL.appendingPathComponent("workspace-library.sqlite", isDirectory: false)
    }

    var cloneLibraryURL: URL {
        baseURL.appendingPathComponent("clones", isDirectory: true)
    }

    static func live(fileManager: FileManager = .default) -> AppStoragePaths {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RustGoblin", isDirectory: true)
        return AppStoragePaths(baseURL: baseURL)
    }

    static func temporary(rootName: String = UUID().uuidString, fileManager: FileManager = .default) -> AppStoragePaths {
        AppStoragePaths(baseURL: fileManager.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true))
    }

    func ensureDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cloneLibraryURL, withIntermediateDirectories: true)
    }
}
