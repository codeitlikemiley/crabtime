import CryptoKit
import Foundation

struct WorkspaceBaselineStore: Sendable {
    let baselineLibraryURL: URL

    init(baselineLibraryURL: URL) {
        self.baselineLibraryURL = baselineLibraryURL
    }

    func hasBaseline(for workspaceRootURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: baselineURL(for: workspaceRootURL).path)
    }

    func captureBaseline(from workspaceRootURL: URL) throws {
        let snapshotURL = baselineURL(for: workspaceRootURL)
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            try FileManager.default.removeItem(at: snapshotURL)
        }

        try copyDirectory(from: workspaceRootURL, to: snapshotURL)
    }

    func deleteBaseline(for workspaceRootURL: URL) throws {
        let snapshotURL = baselineURL(for: workspaceRootURL)
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: snapshotURL)
    }

    func restoreBaseline(to workspaceRootURL: URL) throws {
        let snapshotURL = baselineURL(for: workspaceRootURL)
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            throw NSError(
                domain: "WorkspaceBaselineStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No baseline snapshot exists for this workspace."]
            )
        }

        if FileManager.default.fileExists(atPath: workspaceRootURL.path) {
            try FileManager.default.removeItem(at: workspaceRootURL)
        }

        try copyDirectory(from: snapshotURL, to: workspaceRootURL)
    }

    func loadBaselineData(for workspace: ExerciseWorkspace) -> [String: Data] {
        let snapshotRootURL = baselineURL(for: workspace.rootURL)
        guard FileManager.default.fileExists(atPath: snapshotRootURL.path) else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: workspaceFileURLs(in: workspace.fileTree).compactMap { fileURL in
                let relativePath = relativePath(for: fileURL, rootURL: workspace.rootURL)
                let baselineFileURL = snapshotRootURL.appendingPathComponent(relativePath)
                guard let data = try? Data(contentsOf: baselineFileURL) else {
                    return nil
                }

                return (fileURL.standardizedFileURL.path, data)
            }
        )
    }

    private func baselineURL(for workspaceRootURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(workspaceRootURL.standardizedFileURL.path.utf8))
        let identifier = digest.compactMap { String(format: "%02x", $0) }.joined()
        return baselineLibraryURL.appendingPathComponent(identifier, isDirectory: true)
    }

    private func copyDirectory(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }

        return fileURL.lastPathComponent
    }

    private func workspaceFileURLs(in nodes: [WorkspaceFileNode]) -> [URL] {
        nodes.flatMap { node in
            if node.isDirectory {
                workspaceFileURLs(in: node.children)
            } else {
                [node.url]
            }
        }
    }
}
