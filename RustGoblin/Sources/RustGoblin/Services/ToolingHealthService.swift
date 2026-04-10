import Foundation

struct ToolingHealthService {
    func collectStatus(exercismCLI: ExercismCLI) async -> [ToolHealthStatus] {
        async let codex = codexStatus()
        async let gemini = cliStatus(
            title: "Gemini CLI",
            subtitle: "Gemini subscription runtime",
            executableName: "gemini",
            versionArguments: ["--version"],
            installHint: "Install Gemini CLI, then authenticate with OAuth or an API key."
        )
        async let claude = cliStatus(
            title: "Claude Code",
            subtitle: "Anthropic CLI runtime",
            executableName: "claude",
            versionArguments: ["--version"],
            installHint: "Install Claude Code and authenticate before using chat."
        )
        async let openCode = openCodeStatus()
        async let cargoRunner = cliStatus(
            title: "Cargo Runner",
            subtitle: "Rust exercise runner",
            executableName: "cargo",
            versionArguments: ["runner", "--help"],
            installHint: "Install cargo-runner and make sure `cargo runner` resolves in PATH."
        )
        async let rustlings = cliStatus(
            title: "Rustlings CLI",
            subtitle: "Rustlings exercise runner",
            executableName: "rustlings",
            versionArguments: ["--version"],
            installHint: "Install with `cargo install rustlings`, then run `rustlings init` if you want the official managed workspace."
        )
        async let cargo = cliStatus(
            title: "Cargo",
            subtitle: "Rust build tool",
            executableName: "cargo",
            versionArguments: ["--version"],
            installHint: "Install Rust with rustup from the official Rust site."
        )
        async let rustc = cliStatus(
            title: "rustc",
            subtitle: "Rust compiler",
            executableName: "rustc",
            versionArguments: ["--version"],
            installHint: "Install Rust with rustup from the official Rust site."
        )
        async let codecrafters = cliStatus(
            title: "Codecrafters CLI",
            subtitle: "Codecrafters workspace tooling",
            executableName: "codecrafters",
            versionArguments: ["--version"],
            installHint: "Install the Codecrafters CLI if you want challenge support here."
        )
        async let exercism = exercismStatus(exercismCLI)

        return await [codex, gemini, claude, openCode, cargoRunner, rustlings, cargo, rustc, codecrafters, exercism]
    }

    private func codexStatus() async -> ToolHealthStatus {
        guard let executableURL = Self.resolveExecutable(named: "codex") else {
            return ToolHealthStatus(
                id: "codex",
                title: "Codex CLI",
                subtitle: "ChatGPT subscription runtime",
                executablePath: nil,
                version: nil,
                isInstalled: false,
                isConfigured: false,
                guidance: "Install Codex CLI and sign in with your ChatGPT subscription."
            )
        }

        let versionResult = try? await Self.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "--version"],
            currentDirectoryURL: nil
        )
        let statusResult = try? await Self.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "login", "status"],
            currentDirectoryURL: nil
        )
        let isConfigured = statusResult?.terminationStatus == 0 && (statusResult?.combinedText.localizedCaseInsensitiveContains("logged in") == true)

        return ToolHealthStatus(
            id: "codex",
            title: "Codex CLI",
            subtitle: "ChatGPT subscription runtime",
            executablePath: executableURL.path,
            version: versionResult?.combinedText.trimmingCharacters(in: .whitespacesAndNewlines),
            isInstalled: true,
            isConfigured: isConfigured,
            guidance: isConfigured ? nil : "Run `codex login` or `codex login status` to finish setup."
        )
    }

    private func openCodeStatus() async -> ToolHealthStatus {
        guard let executableURL = Self.resolveExecutable(named: "opencode") else {
            return ToolHealthStatus(
                id: "opencode",
                title: "OpenCode",
                subtitle: "CLI broker for subscribed providers",
                executablePath: nil,
                version: nil,
                isInstalled: false,
                isConfigured: false,
                guidance: "Install OpenCode and configure a provider."
            )
        }

        let versionResult = try? await Self.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["opencode", "--version"],
            currentDirectoryURL: nil
        )
        let providerResult = try? await Self.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["opencode", "providers", "list"],
            currentDirectoryURL: nil
        )
        let isConfigured = providerResult?.terminationStatus == 0 && !(providerResult?.combinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return ToolHealthStatus(
            id: "opencode",
            title: "OpenCode",
            subtitle: "CLI broker for subscribed providers",
            executablePath: executableURL.path,
            version: versionResult?.combinedText.trimmingCharacters(in: .whitespacesAndNewlines),
            isInstalled: true,
            isConfigured: isConfigured,
            guidance: isConfigured ? nil : "Run `opencode auth login` or configure a provider in OpenCode first."
        )
    }

    private func exercismStatus(_ exercismCLI: ExercismCLI) async -> ToolHealthStatus {
        do {
            let status = try exercismCLI.status()
            return ToolHealthStatus(
                id: "exercism",
                title: "Exercism CLI",
                subtitle: "Exercise download and submission",
                executablePath: status.executableURL?.path,
                version: nil,
                isInstalled: status.isInstalled,
                isConfigured: status.isConfigured,
                guidance: status.isInstalled
                    ? (status.isConfigured ? nil : "Run `exercism configure --token=YOUR_TOKEN` to finish setup.")
                    : "Install with `brew install exercism`."
            )
        } catch {
            return ToolHealthStatus(
                id: "exercism",
                title: "Exercism CLI",
                subtitle: "Exercise download and submission",
                executablePath: nil,
                version: nil,
                isInstalled: false,
                isConfigured: false,
                guidance: error.localizedDescription
            )
        }
    }

    private func cliStatus(
        title: String,
        subtitle: String,
        executableName: String,
        versionArguments: [String],
        installHint: String
    ) async -> ToolHealthStatus {
        guard let executableURL = Self.resolveExecutable(named: executableName) else {
            return ToolHealthStatus(
                id: executableName,
                title: title,
                subtitle: subtitle,
                executablePath: nil,
                version: nil,
                isInstalled: false,
                isConfigured: false,
                guidance: installHint
            )
        }

        let result = try? await Self.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [executableName] + versionArguments,
            currentDirectoryURL: nil
        )
        let versionText = result?.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandSucceeded = result?.terminationStatus == 0

        return ToolHealthStatus(
            id: executableName,
            title: title,
            subtitle: subtitle,
            executablePath: executableURL.path,
            version: versionText?.isEmpty == false ? versionText : nil,
            isInstalled: true,
            isConfigured: commandSucceeded,
            guidance: commandSucceeded ? nil : installHint
        )
    }

    static func resolveExecutable(named executableName: String) -> URL? {
        let environment = DependencyManager.shared.defaultEnvironment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultCandidates = [
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)",
            "/usr/bin/\(executableName)",
            "\(homeDir)/.cargo/bin/\(executableName)"
        ].map(URL.init(fileURLWithPath:))

        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent(executableName) }

        var seen = Set<String>()
        return (defaultCandidates + pathCandidates).first { candidate in
            seen.insert(candidate.path).inserted && FileManager.default.isExecutableFile(atPath: candidate.path)
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        stdin: Data? = nil
    ) async throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
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
                                commandDescription: ([executableURL.lastPathComponent] + arguments).joined(separator: " "),
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
                if let stdin {
                    stdinPipe.fileHandleForWriting.write(stdin)
                }
                try? stdinPipe.fileHandleForWriting.close()
            } catch {
                stdoutTask.cancel()
                stderrTask.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
