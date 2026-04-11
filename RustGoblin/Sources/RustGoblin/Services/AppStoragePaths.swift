import Foundation

struct AppStoragePaths: Equatable, Sendable {
    let baseURL: URL

    var databaseURL: URL {
        baseURL.appendingPathComponent("workspace-library.sqlite", isDirectory: false)
    }

    var cloneLibraryURL: URL {
        baseURL.appendingPathComponent("clones", isDirectory: true)
    }

    var importedLibraryURL: URL {
        baseURL.appendingPathComponent("imports", isDirectory: true)
    }

    var exercismLibraryURL: URL {
        baseURL.appendingPathComponent("exercism", isDirectory: true)
    }

    var createdWorkspaceLibraryURL: URL {
        baseURL.appendingPathComponent("workspaces", isDirectory: true)
    }

    var baselineLibraryURL: URL {
        baseURL.appendingPathComponent("baselines", isDirectory: true)
    }

    var logsURL: URL {
        baseURL.appendingPathComponent("logs", isDirectory: true)
    }

    var acpLogsURL: URL {
        logsURL.appendingPathComponent("acp", isDirectory: true)
    }

    var acpRuntimeURL: URL {
        baseURL.appendingPathComponent("acp-runtime", isDirectory: true)
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
        try fileManager.createDirectory(at: importedLibraryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: exercismLibraryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: createdWorkspaceLibraryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: baselineLibraryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: acpLogsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: acpRuntimeURL, withIntermediateDirectories: true)
    }

    func containsManagedWorkspace(_ url: URL) -> Bool {
        let standardizedPath = url.standardizedFileURL.path
        return standardizedPath.hasPrefix(cloneLibraryURL.standardizedFileURL.path + "/")
            || standardizedPath.hasPrefix(importedLibraryURL.standardizedFileURL.path + "/")
            || standardizedPath.hasPrefix(exercismLibraryURL.standardizedFileURL.path + "/")
            || standardizedPath.hasPrefix(createdWorkspaceLibraryURL.standardizedFileURL.path + "/")
    }
}
