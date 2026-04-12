import Foundation

struct WorkspaceFileChangeService: Sendable {
    typealias ProcessRunner = @Sendable (URL, [String]) async throws -> ProcessOutput

    private let processRunner: ProcessRunner

    init(processRunner: ProcessRunner? = nil) {
        self.processRunner = processRunner ?? Self.runProcess(currentDirectoryURL:arguments:)
    }

    func diff(
        original: String,
        modified: String,
        originalLabel: String,
        modifiedLabel: String
    ) async throws -> String {
        if original == modified {
            return ""
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppBrand.diffTempDirectoryPrefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let originalURL = tempDirectory.appendingPathComponent("original.txt")
        let modifiedURL = tempDirectory.appendingPathComponent("modified.txt")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try original.write(to: originalURL, atomically: true, encoding: .utf8)
        try modified.write(to: modifiedURL, atomically: true, encoding: .utf8)

        let result = try await processRunner(
            tempDirectory,
            ["git", "diff", "--no-index", "--no-color", "--src-prefix=\(originalLabel)/", "--dst-prefix=\(modifiedLabel)/", originalURL.lastPathComponent, modifiedURL.lastPathComponent]
        )

        return result.combinedText
    }

    func gitRepositoryRoot(for fileURL: URL) async throws -> URL? {
        let directoryURL = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
        let result = try await processRunner(directoryURL, ["git", "rev-parse", "--show-toplevel"])
        guard result.terminationStatus == 0 else {
            return nil
        }

        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    func gitHeadContent(for fileURL: URL, repositoryRootURL: URL) async throws -> String? {
        let relativePath = relativePath(for: fileURL, rootURL: repositoryRootURL)
        let result = try await processRunner(repositoryRootURL, ["git", "show", "HEAD:\(relativePath)"])
        guard result.terminationStatus == 0 else {
            return nil
        }

        return result.stdout
    }

    func restoreFileFromGit(_ fileURL: URL, repositoryRootURL: URL) async throws {
        let relativePath = relativePath(for: fileURL, rootURL: repositoryRootURL)
        let result = try await processRunner(repositoryRootURL, ["git", "restore", "--", relativePath])
        guard result.terminationStatus == 0 else {
            throw NSError(
                domain: "WorkspaceFileChangeService",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: result.combinedText.isEmpty ? "git restore failed." : result.combinedText]
            )
        }
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String {
        fileURL.standardizedFileURL.path.replacingOccurrences(of: rootURL.standardizedFileURL.path + "/", with: "")
    }

    private static func runProcess(
        currentDirectoryURL: URL,
        arguments: [String]
    ) async throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task.detached {
            try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
        }
        let stderrTask = Task.detached {
            try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                Task {
                    do {
                        let stdoutData = try await stdoutTask.value
                        let stderrData = try await stderrTask.value

                        continuation.resume(
                            returning: ProcessOutput(
                                commandDescription: arguments.joined(separator: " "),
                                stdout: String(decoding: stdoutData, as: UTF8.self),
                                stderr: String(decoding: stderrData, as: UTF8.self),
                                terminationStatus: terminatedProcess.terminationStatus
                            )
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                stdoutTask.cancel()
                stderrTask.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
