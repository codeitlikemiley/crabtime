import Foundation

struct ToolingHealthService {
    func collectStatusStream(exercismCLI: ExercismCLI) -> AsyncStream<ToolHealthStatus> {
        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: ToolHealthStatus.self) { group in
                    group.addTask { await self.codexStatus() }
                    group.addTask {
                        await self.cliStatus(
                            title: "Gemini CLI",
                            subtitle: "Gemini subscription runtime",
                            executableName: "gemini",
                            versionArguments: ["--version"],
                            installHint: "Install Gemini CLI, then authenticate with OAuth or an API key.",
                            installCommand: "npm install -g @google/generative-ai-cli"
                        )
                    }
                    group.addTask {
                        await self.cliStatus(
                            title: "Claude Code",
                            subtitle: "Anthropic CLI runtime",
                            executableName: "claude",
                            versionArguments: ["--version"],
                            installHint: "Install Claude Code and authenticate before using chat.",
                            installCommand: "npm install -g @anthropic-ai/claude-code"
                        )
                    }
                    group.addTask { await self.openCodeStatus() }
                    group.addTask {
                        await self.cliStatus(
                            title: "Cargo Runner",
                            subtitle: "Rust exercise runner",
                            executableName: "cargo",
                            versionArguments: ["runner", "--help"],
                            installHint: "Install cargo-runner and make sure `cargo runner` resolves in PATH.",
                            installCommand: "cargo install cargo-runner"
                        )
                    }
                    group.addTask {
                        await self.cliStatus(
                            title: "Rustlings CLI",
                            subtitle: "Rustlings exercise runner",
                            executableName: "rustlings",
                            versionArguments: ["--version"],
                            installHint: "Install with `cargo install rustlings`, then run `rustlings init` if you want the official managed workspace.",
                            installCommand: "cargo install rustlings"
                        )
                    }
                    group.addTask {
                        await self.cliStatus(
                            title: "Cargo",
                            subtitle: "Rust build tool",
                            executableName: "cargo",
                            versionArguments: ["--version"],
                            installHint: "Install Rust with rustup from the official Rust site.",
                            installCommand: "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                        )
                    }
                    group.addTask {
                        await self.cliStatus(
                            title: "rustc",
                            subtitle: "Rust compiler",
                            executableName: "rustc",
                            versionArguments: ["--version"],
                            installHint: "Install Rust with rustup from the official Rust site.",
                            installCommand: "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                        )
                    }
                    group.addTask {
                        await self.cliStatus(
                            title: "Codecrafters CLI",
                            subtitle: "Codecrafters workspace tooling",
                            executableName: "codecrafters",
                            versionArguments: ["--version"],
                            installHint: "Install the Codecrafters CLI if you want challenge support here.",
                            installCommand: "curl https://codecrafters.io/install.sh | sh"
                        )
                    }
                    group.addTask { await self.exercismStatus(exercismCLI) }

                    for await status in group {
                        continuation.yield(status)
                    }
                }
                continuation.finish()
            }
        }
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
                guidance: "Install Codex CLI and sign in with your ChatGPT subscription.",
                installCommand: "npm install -g @openai/codex-cli"
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
            guidance: isConfigured ? nil : "Run `codex login` or `codex login status` to finish setup.",
            installCommand: nil
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
                guidance: "Install OpenCode and configure a provider.",
                installCommand: "npm install -g @open-code/cli"
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
            guidance: isConfigured ? nil : "Run `opencode auth login` or configure a provider in OpenCode first.",
            installCommand: nil
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
                    : "Install with `brew install exercism`.",
                installCommand: status.isInstalled ? nil : "brew install exercism"
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
                guidance: error.localizedDescription,
                installCommand: nil
            )
        }
    }

    private func cliStatus(
        title: String,
        subtitle: String,
        executableName: String,
        versionArguments: [String],
        installHint: String,
        installCommand: String?
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
                guidance: installHint,
                installCommand: installCommand
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
            guidance: commandSucceeded ? nil : installHint,
            installCommand: nil
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
        try await UnifiedProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL ?? FileManager.default.temporaryDirectory,
            stdin: stdin
        )
    }
}
