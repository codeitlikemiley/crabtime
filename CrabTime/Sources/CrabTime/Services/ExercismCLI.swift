import Foundation

struct ExercismCLI: Sendable {
    struct Status: Equatable, Sendable {
        let executableURL: URL?
        let configFileURL: URL
        let workspaceURL: URL?
        let hasToken: Bool

        var isInstalled: Bool {
            executableURL != nil
        }

        var isConfigured: Bool {
            isInstalled && hasToken && workspaceURL != nil
        }
    }

    typealias ExecutableResolver = @Sendable () -> URL?
    typealias ProcessRunner = @Sendable (URL, [String], URL?) async throws -> ProcessOutput

    private struct ConfigFile: Decodable {
        let token: String?
        let workspace: String?
    }

    private let configFileURL: URL
    private let executableResolver: ExecutableResolver
    private let processRunner: ProcessRunner

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        configFileURL: URL? = nil,
        executableResolver: ExecutableResolver? = nil,
        processRunner: ProcessRunner? = nil
    ) {
        if let configFileURL {
            self.configFileURL = configFileURL
        } else if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
            self.configFileURL = URL(fileURLWithPath: xdgConfigHome, isDirectory: true)
                .appendingPathComponent("exercism", isDirectory: true)
                .appendingPathComponent("user.json", isDirectory: false)
        } else {
            self.configFileURL = homeDirectoryURL
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("exercism", isDirectory: true)
                .appendingPathComponent("user.json", isDirectory: false)
        }

        let candidateExecutableURLs = Self.candidateExecutableURLs(environment: environment)
        self.executableResolver = executableResolver ?? {
            candidateExecutableURLs.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }
        self.processRunner = processRunner ?? Self.runProcess(executableURL:arguments:currentDirectoryURL:)
    }

    func status() throws -> Status {
        let config = try loadConfigFile()
        let token = config?.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspacePath = config?.workspace?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Status(
            executableURL: executableResolver(),
            configFileURL: configFileURL,
            workspaceURL: workspacePath.flatMap { path in
                guard !path.isEmpty else {
                    return nil
                }

                return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            },
            hasToken: !(token?.isEmpty ?? true)
        )
    }

    func configure(token: String) async throws -> ProcessOutput {
        let currentStatus = try status()

        guard let executableURL = currentStatus.executableURL else {
            throw CLIError.notInstalled
        }

        let result = try await processRunner(
            executableURL,
            ["configure", "--token=\(token)"],
            nil
        )

        if result.terminationStatus != 0 || result.combinedText.contains("Error:") {
            throw CLIError.invalidConfiguration(message: result.combinedText)
        }

        return result
    }

    func download(track: String, exercise: String) async throws -> URL {
        let normalizedTrack = try normalizedArgument(track, fieldName: "track")
        let normalizedExercise = try normalizedArgument(exercise, fieldName: "exercise")
        let currentStatus = try status()

        guard let executableURL = currentStatus.executableURL else {
            throw CLIError.notInstalled
        }

        guard currentStatus.hasToken else {
            throw CLIError.missingToken(configFileURL: currentStatus.configFileURL)
        }

        guard let workspaceURL = currentStatus.workspaceURL else {
            throw CLIError.missingWorkspace(configFileURL: currentStatus.configFileURL)
        }

        let result = try await processRunner(
            executableURL,
            [
                "download",
                "--track=\(normalizedTrack)",
                "--exercise=\(normalizedExercise)"
            ],
            workspaceURL
        )

        let fallbackURL = workspaceURL
            .appendingPathComponent(normalizedTrack, isDirectory: true)
            .appendingPathComponent(normalizedExercise, isDirectory: true)
            .standardizedFileURL

        if result.terminationStatus == 0 {
            if let parsedURL = parseDownloadedURL(from: result.combinedText) {
                return parsedURL
            }

            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                return fallbackURL
            }

            throw CLIError.destinationNotFound(message: result.combinedText)
        }

        if let existingURL = parseExistingDirectoryURL(from: result.combinedText) {
            return existingURL
        }

        throw CLIError.downloadFailed(message: result.combinedText)
    }

    func submit(exerciseDirectoryURL: URL, files: [String] = []) async throws -> ProcessOutput {
        let currentStatus = try status()

        guard let executableURL = currentStatus.executableURL else {
            throw CLIError.notInstalled
        }

        guard currentStatus.hasToken else {
            throw CLIError.missingToken(configFileURL: currentStatus.configFileURL)
        }

        let sanitizedFiles = files
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let result = try await processRunner(
            executableURL,
            ["submit"] + sanitizedFiles,
            exerciseDirectoryURL
        )

        if result.terminationStatus != 0 {
            if result.combinedText.contains("No files you submitted have changed") {
                return result
            }
            throw CLIError.submitFailed(message: result.combinedText)
        }

        return result
    }

    private func loadConfigFile() throws -> ConfigFile? {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: configFileURL)
            return try JSONDecoder().decode(ConfigFile.self, from: data)
        } catch {
            throw CLIError.invalidConfiguration(message: error.localizedDescription)
        }
    }

    private func normalizedArgument(_ value: String, fieldName: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

        guard !trimmed.isEmpty else {
            throw CLIError.invalidArgument(fieldName: fieldName)
        }

        guard trimmed.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw CLIError.invalidArgument(fieldName: fieldName)
        }

        return trimmed.lowercased()
    }

    private func parseDownloadedURL(from text: String) -> URL? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            if line == "Downloaded to", lines.indices.contains(index + 1) {
                return URL(fileURLWithPath: lines[index + 1], isDirectory: true).standardizedFileURL
            }

            if line.hasPrefix("Downloaded to ") {
                let path = String(line.dropFirst("Downloaded to ".count))
                return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            }
        }

        return nil
    }

    private func parseExistingDirectoryURL(from text: String) -> URL? {
        guard let range = text.range(of: "directory '") else {
            return nil
        }

        let pathStart = range.upperBound
        guard let closingRange = text[pathStart...].range(of: "'") else {
            return nil
        }

        let path = String(text[pathStart..<closingRange.lowerBound])
        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func candidateExecutableURLs(environment: [String: String]) -> [URL] {
        var candidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/exercism"),
            URL(fileURLWithPath: "/usr/local/bin/exercism"),
            URL(fileURLWithPath: "/usr/bin/exercism")
        ]

        if let path = environment["PATH"], !path.isEmpty {
            candidates.append(
                contentsOf: path
                    .split(separator: ":")
                    .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("exercism", isDirectory: false) }
            )
        }

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.path).inserted }
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = DependencyManager.shared.defaultEnvironment

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
                                commandDescription: ([executableURL.path] + arguments).joined(separator: " "),
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

extension ExercismCLI {
    enum CLIError: LocalizedError {
        case notInstalled
        case missingToken(configFileURL: URL)
        case missingWorkspace(configFileURL: URL)
        case invalidArgument(fieldName: String)
        case invalidConfiguration(message: String)
        case destinationNotFound(message: String)
        case downloadFailed(message: String)
        case submitFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return """
                Exercism CLI is not installed.

                Install it on macOS with:
                brew install exercism
                """
            case .missingToken(let configFileURL):
                return """
                Exercism CLI is installed, but no API token is configured.

                Find your token at:
                https://exercism.org/settings/api_cli

                Then run:
                exercism configure --token=YOUR_TOKEN

                Config file:
                \(configFileURL.path)
                """
            case .missingWorkspace(let configFileURL):
                return """
                Exercism CLI is installed, but no workspace is configured.

                Configure it with:
                exercism configure --workspace=\"$HOME/Exercism\" --token=YOUR_TOKEN

                Config file:
                \(configFileURL.path)
                """
            case .invalidArgument(let fieldName):
                return "Enter a valid Exercism \(fieldName)."
            case .invalidConfiguration(let message):
                return "Exercism CLI configuration is invalid: \(message)"
            case .destinationNotFound(let message):
                return "Exercism download completed, but \(AppBrand.shortName) could not determine the downloaded folder.\n\n\(message.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .downloadFailed(let message):
                return "Exercism download failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .submitFailed(let message):
                return "Exercism submit failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
    }
}
