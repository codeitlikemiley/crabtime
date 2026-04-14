import Foundation

/// A CLI wrapper for interacting with the `codecrafters` binary
struct CodeCraftersCLI: Sendable {
    struct Status: Equatable, Sendable {
        let executableURL: URL?
        var isInstalled: Bool { executableURL != nil }
    }
    
    typealias ExecutableResolver = @Sendable () -> URL?
    typealias ProcessRunner = @Sendable (URL, [String], URL?) async throws -> ProcessOutput
    
    private let executableResolver: ExecutableResolver
    private let processRunner: ProcessRunner
    
    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableResolver: ExecutableResolver? = nil,
        processRunner: ProcessRunner? = nil
    ) {
        let candidateExecutableURLs = Self.candidateExecutableURLs(environment: environment)
        self.executableResolver = executableResolver ?? {
            candidateExecutableURLs.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }
        self.processRunner = processRunner ?? { executableURL, arguments, currentDirectoryURL in
            try await UnifiedProcessRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL ?? FileManager.default.temporaryDirectory
            )
        }
    }
    
    func status() throws -> Status {
        Status(executableURL: executableResolver())
    }
    
    func ping() async throws -> ProcessOutput {
        let currentStatus = try status()
        guard let executableURL = currentStatus.executableURL else {
            throw CLIError.notInstalled
        }
        
        let result = try await processRunner(executableURL, ["ping"], nil)
        if result.terminationStatus != 0 {
            throw CLIError.notAuthenticated(message: result.combinedText)
        }
        return result
    }
    
    func submit(workspaceDirectoryURL: URL) async throws -> ProcessOutput {
        let currentStatus = try status()
        guard let executableURL = currentStatus.executableURL else {
            throw CLIError.notInstalled
        }
        
        // Streams git push and test outputs back from codecrafters servers.
        let result = try await processRunner(executableURL, ["submit"], workspaceDirectoryURL)
        return result
    }
    
    static func parseFeedbackURL(from text: String) -> URL? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("View results: ") {
                if let urlRange = line.range(of: "https://") {
                    let urlString = String(line[urlRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return URL(string: urlString)
                }
            }
        }
        // Sometimes it outputs View your code at: https://app.codecrafters.io/...
        for line in lines {
            if line.contains("codecrafters.io") && line.contains("https://") {
                if let urlRange = line.range(of: "https://") {
                    let urlString = String(line[urlRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return URL(string: urlString)
                }
            }
        }
        return nil
    }
    
    private static func candidateExecutableURLs(environment: [String: String]) -> [URL] {
        var candidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codecrafters"),
            URL(fileURLWithPath: "/usr/local/bin/codecrafters"),
            URL(fileURLWithPath: "/usr/bin/codecrafters")
        ]
        
        if let path = environment["PATH"], !path.isEmpty {
            candidates.append(
                contentsOf: path
                    .split(separator: ":")
                    .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codecrafters", isDirectory: false) }
            )
        }
        
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.path).inserted }
    }
}

extension CodeCraftersCLI {
    enum CLIError: LocalizedError {
        case notInstalled
        case notAuthenticated(message: String)
        case submitFailed(message: String)
        
        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "CodeCrafters CLI is not installed.\nInstall it using: curl -fsSL https://codecrafters.io/install.sh | bash"
            case .notAuthenticated(let message):
                return "CodeCrafters CLI is not authenticated.\n\(message)"
            case .submitFailed(let message):
                return "CodeCrafters submit failed:\n\(message)"
            }
        }
    }
}
