import AppKit
import Foundation

actor ACPTransportService {
    private struct ConnectionKey: Hashable, Sendable {
        let provider: AIProviderKind
        let workspaceRootPath: String
        let model: String
    }

    private let appPaths: AppStoragePaths
    private let credentialStore: CredentialStore
    private var connections: [ConnectionKey: ACPConnection] = [:]

    init(appPaths: AppStoragePaths, credentialStore: CredentialStore) {
        self.appPaths = appPaths
        self.credentialStore = credentialStore
    }

    func sendMessage(
        provider: AIProviderKind,
        model: String,
        workspaceRootPath: String,
        existingSessionID: String?,
        prompt: String,
        eventSink: (@Sendable (AITransportEvent) -> Void)? = nil
    ) async throws -> AIProviderReply {
        let key = ConnectionKey(provider: provider, workspaceRootPath: workspaceRootPath, model: model)
        let connection: ACPConnection

        if let existing = connections[key] {
            connection = existing
        } else {
            connection = try ACPConnection(
                provider: provider,
                model: model,
                workspaceRootPath: workspaceRootPath,
                appPaths: appPaths,
                credentialStore: credentialStore
            )
            connections[key] = connection
        }

        return try await connection.sendPrompt(
            existingSessionID: existingSessionID,
            prompt: prompt,
            eventSink: eventSink
        )
    }

    func restartConnection(
        provider: AIProviderKind,
        model: String,
        workspaceRootPath: String,
        eventSink: (@Sendable (AITransportEvent) -> Void)? = nil
    ) async {
        let key = ConnectionKey(provider: provider, workspaceRootPath: workspaceRootPath, model: model)
        if let connection = connections.removeValue(forKey: key) {
            eventSink?(.processState(provider: provider, status: "Reconnecting", logFilePath: nil))
            await connection.shutdown(reason: "manual reconnect", emitError: false, eventSink: eventSink)
        }
    }

    func shutdownConnectionsForProvider(
        _ provider: AIProviderKind,
        reason: String,
        eventSink: (@Sendable (AITransportEvent) -> Void)? = nil
    ) async {
        let matchingKeys = connections.keys.filter { $0.provider == provider }
        for key in matchingKeys {
            if let connection = connections.removeValue(forKey: key) {
                await connection.shutdown(reason: reason, emitError: false, eventSink: eventSink)
            }
        }
    }
}

private actor ACPConnection {
    private enum TimeoutProfile {
        static let initialize: Duration = .seconds(90)
        static let session: Duration = .seconds(90)
        static let authenticate: Duration = .seconds(90)
        static let prompt: Duration = .seconds(180)
    }

    private struct LaunchConfiguration {
        let command: String
        let arguments: [String]
        let environment: [String: String]
        let displayCommand: String
        let logPrefix: String
    }

    private struct AuthMethod {
        let id: String
        let name: String
        let description: String?
    }

    private struct PromptAccumulator {
        var assistantText = ""
        var observedToolTitles = Set<String>()
        /// Captured at creation time; calling it from within the actor is safe since the actor
        /// serialises all mutations. `@Sendable` ensures the closure can cross actor boundaries.
        let eventSink: (@Sendable (AITransportEvent) -> Void)?
    }

    private let provider: AIProviderKind
    private let model: String
    private let workspaceRootPath: String
    private let credentialStore: CredentialStore
    private let launchConfiguration: LaunchConfiguration
    private let logFileURL: URL

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutReadHandle: FileHandle?
    private var stderrReadHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var didInitialize = false
    private var supportsLoadSession = false
    private var authMethods: [AuthMethod] = []
    private var nextRequestID = 1
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var activePrompts: [String: PromptAccumulator] = [:]
    private var loadedSessionIDs: Set<String> = []
    private var hasAttemptedAuthentication = false
    private var didRecoverStaleSession = false
    private var disablesProactiveAuthentication = false
    private var hasRetriedInitializationWithoutProactiveAuth = false
    private var hasRetriedSessionCreationAfterTimeout = false

    init(
        provider: AIProviderKind,
        model: String,
        workspaceRootPath: String,
        appPaths: AppStoragePaths,
        credentialStore: CredentialStore
    ) throws {
        self.provider = provider
        self.model = model
        self.workspaceRootPath = workspaceRootPath
        self.credentialStore = credentialStore
        self.launchConfiguration = try Self.makeLaunchConfiguration(
            provider: provider,
            model: model,
            workspaceRootPath: workspaceRootPath,
            appPaths: appPaths
        )

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let workspaceName = URL(fileURLWithPath: workspaceRootPath).lastPathComponent
        let sanitizedModel = model.replacingOccurrences(of: "/", with: "_")
        let fileName = "\(provider.rawValue)-\(workspaceName)-\(sanitizedModel)-\(timestamp).log"
        self.logFileURL = appPaths.acpLogsURL.appendingPathComponent(fileName, isDirectory: false)

        try appPaths.ensureDirectories()
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    func sendPrompt(
        existingSessionID: String?,
        prompt: String,
        eventSink: (@Sendable (AITransportEvent) -> Void)?
    ) async throws -> AIProviderReply {
        try await ensureInitialized(eventSink: eventSink)
        didRecoverStaleSession = false

        let sessionID = try await resolveSessionID(existingSessionID: existingSessionID, eventSink: eventSink)
        let accumulator = PromptAccumulator(assistantText: "", observedToolTitles: [], eventSink: eventSink)
        activePrompts[sessionID] = accumulator
        defer { activePrompts.removeValue(forKey: sessionID) }

        let result = try await sendRequest(
            method: "session/prompt",
            params: [
                "sessionId": sessionID,
                "prompt": [
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ],
            timeout: TimeoutProfile.prompt
        )

        let stopReason = Self.string(in: result, key: "stopReason") ?? "end_turn"
        await logLine("[response] stop_reason=\(stopReason) session=\(sessionID)")

        // Read the final accumulator state from the dictionary (struct is value type;
        // mutations during sendRequest went through activePrompts[sessionID]?.property).
        let finalAccumulator = activePrompts[sessionID]
        finalAccumulator?.eventSink?(.note(provider: provider, message: "ACP stop reason: \(stopReason)"))

        let responseText = (finalAccumulator?.assistantText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !responseText.isEmpty else {
            throw AIProviderError.emptyResponse(provider.title)
        }

        return AIProviderReply(
            content: responseText,
            backendSessionID: sessionID,
            didRecoverStaleSession: didRecoverStaleSession
        )
    }

    private func ensureInitialized(
        eventSink: (@Sendable (AITransportEvent) -> Void)?
    ) async throws {
        guard !didInitialize else {
            return
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [launchConfiguration.command] + launchConfiguration.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        process.environment = launchConfiguration.environment
        process.terminationHandler = { terminatedProcess in
            Task {
                await self.handleTermination(terminatedProcess: terminatedProcess, status: terminatedProcess.terminationStatus)
            }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutReadHandle = stdoutPipe.fileHandleForReading
        self.stderrReadHandle = stderrPipe.fileHandleForReading
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)

        await logLine("[launch] \(launchConfiguration.displayCommand)")
        let environmentSummary = Self.launchEnvironmentSummary(launchConfiguration.environment)
        await logLine("[launch-env] \(environmentSummary)")
        eventSink?(.processState(provider: provider, status: "Launching", logFilePath: logFileURL.path))

        stdoutReadHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.handleStdoutData(data)
            }
        }

        stderrReadHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.handleStderrData(data)
            }
        }

        let initializeResult = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": false,
                        "writeTextFile": false
                    ],
                    "terminal": false
                ],
                "clientInfo": [
                    "name": AppBrand.longName,
                    "version": "0.1"
                ]
            ],
            timeout: TimeoutProfile.initialize
        )

        supportsLoadSession = Self.bool(in: initializeResult, path: ["agentCapabilities", "loadSession"]) ?? false
        authMethods = Self.arrayOfDictionaries(in: initializeResult, key: "authMethods").compactMap { method in
            guard let id = Self.string(in: method, key: "id"),
                  let name = Self.string(in: method, key: "name")
            else {
                return nil
            }
            return AuthMethod(id: id, name: name, description: Self.string(in: method, key: "description"))
        }

        if providerRequiresProactiveAuth && !disablesProactiveAuthentication {
            do {
                try await performProactiveAuthentication(eventSink: eventSink)
            } catch {
                guard Self.isTimeoutError(error), !hasRetriedInitializationWithoutProactiveAuth else {
                    throw error
                }

                hasRetriedInitializationWithoutProactiveAuth = true
                disablesProactiveAuthentication = true
                await logLine("[auth] proactive auth unavailable, restarting ACP without authenticate: \(error.localizedDescription)")
                eventSink?(.note(provider: provider, message: "ACP authenticate did not respond. Restarting Gemini ACP without re-authentication."))
                eventSink?(.authState(provider: provider, status: "Using existing Gemini CLI auth state"))
                await shutdown(reason: "retry without proactive auth", emitError: false, eventSink: eventSink)
                return try await ensureInitialized(eventSink: eventSink)
            }
        }

        didInitialize = true
        await logLine("[initialize] loadSession=\(supportsLoadSession) authMethods=\(authMethods.map(\.id).joined(separator: ","))")
    }

    private func resolveSessionID(
        existingSessionID: String?,
        eventSink: (@Sendable (AITransportEvent) -> Void)?
    ) async throws -> String {
        if let existingSessionID, loadedSessionIDs.contains(existingSessionID) {
            return existingSessionID
        }

        if let existingSessionID, supportsLoadSession {
            do {
                _ = try await sendRequest(
                    method: "session/load",
                    params: [
                        "sessionId": existingSessionID,
                        "cwd": workspaceRootPath,
                        "mcpServers": []
                    ],
                    timeout: sessionRequestTimeout
                )
                loadedSessionIDs.insert(existingSessionID)
                await logLine("[session] loaded \(existingSessionID)")
                eventSink?(.sessionReady(
                    provider: provider,
                    transport: .acp,
                    sessionID: existingSessionID,
                    reused: true,
                    logFilePath: logFileURL.path
                ))
                return existingSessionID
            } catch {
                if try await attemptAuthenticationIfNeeded(after: error, eventSink: eventSink) {
                    return try await resolveSessionID(existingSessionID: existingSessionID, eventSink: eventSink)
                }

                await logLine("[session] load_failed \(existingSessionID) error=\(error.localizedDescription)")
                didRecoverStaleSession = true
                eventSink?(.note(provider: provider, message: "Stored ACP session became invalid. Creating a fresh session."))
            }
        }

        do {
            let result = try await sendRequest(
                method: "session/new",
                params: [
                    "cwd": workspaceRootPath,
                    "mcpServers": []
                ],
                timeout: sessionRequestTimeout
            )
            guard let sessionID = Self.string(in: result, key: "sessionId") else {
                throw AIProviderError.runtimeFailure("ACP session/new did not return a sessionId.")
            }
            loadedSessionIDs.insert(sessionID)
            await logLine("[session] created \(sessionID)")
            eventSink?(.sessionReady(
                provider: provider,
                transport: .acp,
                sessionID: sessionID,
                reused: false,
                logFilePath: logFileURL.path
            ))
            return sessionID
        } catch {
            if provider == .geminiCLI,
               Self.isTimeoutError(error),
               !hasRetriedSessionCreationAfterTimeout
            {
                hasRetriedSessionCreationAfterTimeout = true
                await logLine("[session] session/new timed out, restarting ACP and retrying once")
                eventSink?(.note(provider: provider, message: "Gemini ACP session start timed out. Restarting and retrying once."))
                await shutdown(reason: "retry after session/new timeout", emitError: false, eventSink: eventSink)
                try await ensureInitialized(eventSink: eventSink)
                return try await resolveSessionID(existingSessionID: nil, eventSink: eventSink)
            }
            if try await attemptAuthenticationIfNeeded(after: error, eventSink: eventSink) {
                return try await resolveSessionID(existingSessionID: nil, eventSink: eventSink)
            }
            throw error
        }
    }

    private func attemptAuthenticationIfNeeded(
        after error: Error,
        eventSink: (@Sendable (AITransportEvent) -> Void)?
    ) async throws -> Bool {
        guard !hasAttemptedAuthentication else {
            return false
        }
        guard !authMethods.isEmpty else {
            return false
        }

        let message = error.localizedDescription.lowercased()
        guard message.contains("auth")
            || message.contains("login")
            || message.contains("credential")
            || message.contains("oauth")
            || message.contains("permission")
        else {
            return false
        }

        hasAttemptedAuthentication = true
        let methodID = preferredAuthenticationMethodID() ?? authMethods.first?.id
        guard let methodID else {
            return false
        }

        let methodName = authMethods.first(where: { $0.id == methodID })?.name ?? methodID
        await logLine("[auth] authenticate \(methodID)")
        eventSink?(.authState(provider: provider, status: "Authenticating via \(methodName)"))
        do {
            _ = try await sendRequest(
                method: "authenticate",
                params: [
                    "methodId": methodID
                ]
            )
        } catch {
            eventSink?(.authState(provider: provider, status: "Authentication failed"))
            throw error
        }
        eventSink?(.authState(provider: provider, status: "Authenticated via \(methodName)"))
        return true
    }

    private func preferredAuthenticationMethodID() -> String? {
        switch provider {
        case .geminiCLI:
            if authMethods.contains(where: { $0.id == "oauth-personal" }) {
                return "oauth-personal"
            }
            return authMethods.first?.id
        case .openCodeCLI:
            return authMethods.first(where: { $0.id == "opencode-login" })?.id ?? authMethods.first?.id
        case .codexCLI:
            return authMethods.first?.id
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            return nil
        }
    }

    /// Providers that silently hang on session/new without prior authentication.
    private var providerRequiresProactiveAuth: Bool {
        switch provider {
        case .geminiCLI:
            return false
        case .openCodeCLI, .codexCLI, .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            return false
        }
    }

    private var sessionRequestTimeout: Duration {
        switch provider {
        case .geminiCLI:
            return .seconds(180)
        case .openCodeCLI, .codexCLI, .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            return TimeoutProfile.session
        }
    }

    /// Authenticate immediately after initialize to prevent silent hangs.
    private func performProactiveAuthentication(
        eventSink: (@Sendable (AITransportEvent) -> Void)?
    ) async throws {
        let methodID = preferredAuthenticationMethodID() ?? authMethods.first?.id
        guard let methodID else {
            await logLine("[auth] no suitable auth method found, skipping proactive auth")
            return
        }

        let methodName = authMethods.first(where: { $0.id == methodID })?.name ?? methodID
        await logLine("[auth] proactive authenticate \(methodID)")
        eventSink?(.authState(provider: provider, status: "Authenticating via \(methodName)"))

        do {
            _ = try await sendRequest(
                method: "authenticate",
                params: ["methodId": methodID],
                timeout: TimeoutProfile.authenticate
            )
            hasAttemptedAuthentication = true
            await logLine("[auth] proactive auth succeeded via \(methodID)")
            eventSink?(.authState(provider: provider, status: "Authenticated via \(methodName)"))
        } catch {
            await logLine("[auth] proactive auth failed: \(error.localizedDescription)")
            eventSink?(.authState(provider: provider, status: "Authentication failed: \(error.localizedDescription)"))
            throw error
        }
    }

    private func sendRequest(
        method: String,
        params: [String: Any],
        timeout: Duration? = nil
    ) async throws -> [String: Any] {
        let requestID = String(nextRequestID)
        nextRequestID += 1

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int(requestID) ?? requestID,
            "method": method,
            "params": params
        ]

        let payloadData: Data
        do {
            payloadData = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Store the continuation FIRST, before writing the request.
            // This prevents a race where the response arrives and
            // handleStdoutLine looks up pendingResponses before the
            // continuation has been registered.
            pendingResponses[requestID] = continuation

            // Set up timeout cancellation.
            if let timeout {
                Task { [provider, weak self] in
                    try? await Task.sleep(for: timeout)
                    await self?.cancelPendingResponse(
                        requestID: requestID,
                        error: AIProviderError.runtimeFailure(
                            "\(provider.title) ACP request '\(method)' timed out."
                        )
                    )
                }
            }

            // Now write the request. If this fails, cancel the pending
            // continuation so the caller doesn't hang.
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.writeData(payloadData)
                } catch {
                    await self.cancelPendingResponse(
                        requestID: requestID,
                        error: error
                    )
                }
            }
        }
    }

    private func cancelPendingResponse(
        requestID: String,
        error: Error
    ) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: error)
    }

    /// Serialises a dictionary payload as JSON and writes it to the process stdin.
    private func writeJSON(_ payload: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await writeData(data)
    }

    /// Writes pre-serialised JSON data to the process stdin, logging the outgoing line.
    private func writeData(_ data: Data) async throws {
        guard let stdinHandle else {
            throw AIProviderError.runtimeFailure("ACP stdin is not available for \(provider.title).")
        }

        if let line = String(data: data, encoding: .utf8) {
            await logLine("[out] \(line)")
        }

        try stdinHandle.write(contentsOf: data + Data([0x0A]))
    }

    private func handleStdoutData(_ data: Data) async {
        if data.isEmpty {
            await flushBufferedStdout(forcePartialLine: true)
            return
        }

        stdoutBuffer.append(data)
        await flushBufferedStdout(forcePartialLine: false)
    }

    private func handleStderrData(_ data: Data) async {
        if data.isEmpty {
            await flushBufferedStderr(forcePartialLine: true)
            return
        }

        stderrBuffer.append(data)
        await flushBufferedStderr(forcePartialLine: false)
    }

    /// Drains newline-delimited lines from a buffer, invoking `handler` for each one.
    /// When `forcePartialLine` is true, any remaining data without a trailing newline
    /// is also emitted and the buffer is cleared (used on EOF / stream close).
    /// Returns the updated buffer to avoid `inout` mutation inside `async` contexts.
    private func flush(
        buffer: Data,
        forcePartialLine: Bool,
        handler: (String) async -> Void
    ) async -> Data {
        var localBuffer = buffer
        while let newlineIndex = localBuffer.firstIndex(of: 0x0A) {
            let lineData = localBuffer.prefix(upTo: newlineIndex)
            localBuffer.removeSubrange(...newlineIndex)
            if let line = String(data: lineData, encoding: .utf8) {
                await handler(line)
            }
        }

        if forcePartialLine, !localBuffer.isEmpty {
            if let line = String(data: localBuffer, encoding: .utf8) {
                await handler(line)
            }
            localBuffer.removeAll(keepingCapacity: false)
        }
        return localBuffer
    }

    private func flushBufferedStdout(forcePartialLine: Bool) async {
        stdoutBuffer = await flush(buffer: stdoutBuffer, forcePartialLine: forcePartialLine) { [self] line in
            await handleStdoutLine(line)
        }
    }

    private func flushBufferedStderr(forcePartialLine: Bool) async {
        stderrBuffer = await flush(buffer: stderrBuffer, forcePartialLine: forcePartialLine) { [self] line in
            await logLine("[stderr] \(line)")
        }
    }

    private func handleStdoutLine(_ line: String) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        await logLine("[in] \(trimmed)")

        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            await logLine("[parse-warning] Non-JSON ACP stdout: \(trimmed)")
            return
        }

        if let method = object["method"] as? String {
            let params = object["params"] as? [String: Any] ?? [:]
            if object["id"] != nil {
                await handleAgentRequest(id: object["id"]!, method: method, params: params)
            } else {
                await handleNotification(method: method, params: params)
            }
            return
        }

        guard let responseID = Self.responseID(from: object["id"]) else {
            return
        }

        guard let continuation = pendingResponses.removeValue(forKey: responseID) else {
            return
        }

        if let error = object["error"] as? [String: Any] {
            continuation.resume(throwing: ACPRequestError.from(error))
            return
        }

        continuation.resume(returning: object["result"] as? [String: Any] ?? [:])
    }

    private func handleAgentRequest(id: Any, method: String, params: [String: Any]) async {
        switch method {
        case "session/request_permission":
            let outcome = await requestPermissionOutcome(for: params)
            do {
                try await writeJSON(
                    [
                        "jsonrpc": "2.0",
                        "id": id,
                        "result": outcome
                    ]
                )
            } catch {
                await logLine("[permission-error] \(error.localizedDescription)")
            }
        default:
            do {
                try await writeJSON(
                    [
                        "jsonrpc": "2.0",
                        "id": id,
                        "error": [
                            "code": -32601,
                            "message": "Unsupported ACP method \(method)"
                        ]
                    ]
                )
            } catch {
                await logLine("[request-error] \(error.localizedDescription)")
            }
        }
    }

    private func handleNotification(method: String, params: [String: Any]) async {
        guard method == "session/update" else {
            return
        }

        guard
            let sessionID = Self.string(in: params, key: "sessionId"),
            let update = Self.dictionary(in: params, key: "update"),
            let updateKind = Self.string(in: update, key: "sessionUpdate"),
            activePrompts[sessionID] != nil
        else {
            return
        }

        // Capture eventSink for read-only calls before the switch; mutations go through
        // the dictionary subscript so they write back to the struct value.
        let eventSink = activePrompts[sessionID]?.eventSink

        switch updateKind {
        case "agent_message_chunk":
            if let text = Self.textChunk(from: update), !text.isEmpty {
                activePrompts[sessionID]?.assistantText += text
            }
        case "agent_thought_chunk":
            break
        case "tool_call":
            let title = Self.string(in: update, key: "title") ?? "Tool call"
            let isNew = activePrompts[sessionID]?.observedToolTitles.insert(title).inserted ?? false
            if isNew {
                let toolCallID = Self.string(in: update, key: "toolCallId") ?? title
                eventSink?(.toolCall(provider: provider, id: toolCallID, title: title, status: "started"))
            }
        case "tool_call_update":
            let title = Self.string(in: update, key: "title") ?? "Tool update"
            let status = Self.string(in: update, key: "status")
            let toolCallID = Self.string(in: update, key: "toolCallId") ?? title
            eventSink?(.toolCall(provider: provider, id: toolCallID, title: title, status: status ?? "updated"))
        case "plan":
            let entries = Self.arrayOfDictionaries(in: update, key: "entries")
            let summary = entries.compactMap { entry -> String? in
                let text = Self.string(in: entry, key: "content") ?? Self.string(in: entry, key: "text")
                let status = Self.string(in: entry, key: "status")
                guard let text else { return nil }
                return status.map { "[\($0)] \(text)" } ?? text
            }.joined(separator: " | ")
            if !summary.isEmpty {
                eventSink?(.note(provider: provider, message: "Plan: \(summary)"))
            }
        case "current_mode_update":
            if let modeID = Self.string(in: update, key: "currentModeId") {
                eventSink?(.note(provider: provider, message: "ACP mode: \(modeID)"))
            }
        case "config_option_update":
            eventSink?(.note(provider: provider, message: "ACP configuration updated"))
        case "available_commands_update":
            let commands = Self.arrayOfDictionaries(in: update, key: "availableCommands")
                .compactMap { Self.string(in: $0, key: "name") }
            if !commands.isEmpty {
                eventSink?(.note(provider: provider, message: "ACP commands: \(commands.joined(separator: ", "))"))
            }
        default:
            break
        }
    }

    private func requestPermissionOutcome(for params: [String: Any]) async -> [String: Any] {
        let toolCall = Self.dictionary(in: params, key: "toolCall")
        let title = toolCall.flatMap { Self.string(in: $0, key: "title") } ?? "ACP tool call"
        let options = Self.arrayOfDictionaries(in: params, key: "options").compactMap { option -> (id: String, name: String)? in
            guard
                let optionID = Self.string(in: option, key: "optionId"),
                let name = Self.string(in: option, key: "name")
            else {
                return nil
            }

            return (optionID, name)
        }

        if options.isEmpty {
            return ["outcome": "cancelled"]
        }

        let selection = await MainActor.run { () -> String? in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = "The ACP agent requested permission before continuing."

            for option in options {
                alert.addButton(withTitle: option.name)
            }
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            let selectedIndex = Int(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            guard selectedIndex >= 0, selectedIndex < options.count else {
                return nil
            }

            return options[selectedIndex].id
        }

        guard let selection else {
            return ["outcome": "cancelled"]
        }

        await logLine("[permission] selected \(selection)")
        return [
            "outcome": "selected",
            "optionId": selection
        ]
    }

    private func handleTermination(terminatedProcess: Process, status: Int32) async {
        await logLine("[exit] status=\(status)")

        if let currentProcess = process, currentProcess !== terminatedProcess {
            await logLine("[exit] ignored stale process termination")
            return
        }

        let error = AIProviderError.runtimeFailure(
            "\(provider.title) ACP process exited with status \(status). Check \(logFileURL.path)."
        )

        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: error)
        }

        pendingResponses.removeAll()
        process = nil
        stdinHandle = nil
        stdoutReadHandle?.readabilityHandler = nil
        stderrReadHandle?.readabilityHandler = nil
        stdoutReadHandle = nil
        stderrReadHandle = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        didInitialize = false
        loadedSessionIDs.removeAll()
    }

    func shutdown(
        reason: String,
        emitError: Bool,
        eventSink: (@Sendable (AITransportEvent) -> Void)?
    ) async {
        await logLine("[shutdown] \(reason)")
        process?.terminate()
        process = nil
        stdinHandle = nil
        stdoutReadHandle?.readabilityHandler = nil
        stderrReadHandle?.readabilityHandler = nil
        stdoutReadHandle = nil
        stderrReadHandle = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        didInitialize = false
        loadedSessionIDs.removeAll()
        pendingResponses.removeAll()
        activePrompts.removeAll()
        if emitError {
            eventSink?(.transportError(provider: provider, message: reason, logFilePath: logFileURL.path))
        }
    }

    private func logLine(_ line: String) async {
        let stamped = "\(Date().formatted(date: .omitted, time: .standard))  \(line)\n"
        if let data = stamped.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }

    private static func makeLaunchConfiguration(
        provider: AIProviderKind,
        model: String,
        workspaceRootPath: String,
        appPaths: AppStoragePaths
    ) throws -> LaunchConfiguration {
        let baseEnvironment = DependencyManager.shared.defaultEnvironment
        let logDirectory = appPaths.acpLogsURL.path

        switch provider {
        case .geminiCLI:
            guard ToolingHealthService.resolveExecutable(named: "gemini") != nil else {
                throw AIProviderError.missingExecutable("gemini")
            }
            return LaunchConfiguration(
                command: "gemini",
                arguments: ["--acp", "-m", model],
                environment: baseEnvironment,
                displayCommand: "gemini --acp -m \(model)",
                logPrefix: "gemini --acp"
            )
        case .openCodeCLI:
            guard ToolingHealthService.resolveExecutable(named: "opencode") != nil else {
                throw AIProviderError.missingExecutable("opencode")
            }
            let overlayURL = appPaths.acpRuntimeURL
                .appendingPathComponent("opencode-\(UUID().uuidString).json", isDirectory: false)
            let overlayData = """
            {
              "$schema": "https://opencode.ai/config.json",
              "model": "\(model)"
            }
            """.data(using: .utf8) ?? Data()
            try overlayData.write(to: overlayURL, options: .atomic)

            var environment = baseEnvironment
            environment["OPENCODE_CONFIG"] = overlayURL.path
            return LaunchConfiguration(
                command: "opencode",
                arguments: ["acp", "--cwd", workspaceRootPath, "--print-logs", "--log-level", "DEBUG"],
                environment: environment,
                displayCommand: "OPENCODE_CONFIG=\(overlayURL.path) opencode acp --cwd \(workspaceRootPath) --print-logs --log-level DEBUG",
                logPrefix: "opencode acp"
            )
        case .codexCLI:
            guard ToolingHealthService.resolveExecutable(named: "codex") != nil else {
                throw AIProviderError.missingExecutable("codex")
            }
            let adapterURL = try resolveCodexACPAdapterURL()

            var environment = baseEnvironment
            environment["RUST_LOG"] = environment["RUST_LOG"] ?? "info"
            environment["CODEX_LOG_DIR"] = logDirectory

            return LaunchConfiguration(
                command: "xcrun",
                arguments: ["swift", adapterURL.path, "--model", model],
                environment: environment,
                displayCommand: "xcrun swift \(adapterURL.path) --model \(model)",
                logPrefix: "codex-acp-adapter"
            )
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            throw AIProviderError.runtimeFailure("\(provider.title) does not expose ACP in this build.")
        }
    }

    private static func responseID(from rawValue: Any?) -> String? {
        switch rawValue {
        case let string as String:
            string
        case let number as NSNumber:
            number.stringValue
        default:
            nil
        }
    }

    private static func dictionary(in object: [String: Any], key: String) -> [String: Any]? {
        object[key] as? [String: Any]
    }

    private static func arrayOfDictionaries(in object: [String: Any], key: String) -> [[String: Any]] {
        object[key] as? [[String: Any]] ?? []
    }

    private static func string(in object: [String: Any], key: String) -> String? {
        object[key] as? String
    }

    private static func bool(in object: [String: Any], path: [String]) -> Bool? {
        var current: Any = object
        for component in path {
            guard let dictionary = current as? [String: Any], let next = dictionary[component] else {
                return nil
            }
            current = next
        }
        return current as? Bool
    }

    private static func textChunk(from update: [String: Any]) -> String? {
        guard let content = update["content"] as? [String: Any] else {
            return nil
        }

        if let text = content["text"] as? String {
            return text
        }

        return nil
    }

    private static func compactLogLine(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(160))
    }

    private static func isTimeoutError(_ error: Error) -> Bool {
        error.localizedDescription.lowercased().contains("timed out")
    }

    private static func launchEnvironmentSummary(_ environment: [String: String]) -> String {
        let keys = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "PATH"]
        return keys.compactMap { key in
            guard let value = environment[key], !value.isEmpty else {
                return "\(key)=<missing>"
            }

            if key == "PATH" {
                return "\(key)=\(compactLogLine(value))"
            }

            return "\(key)=\(value)"
        }.joined(separator: " ")
    }

    private static func resolveCodexACPAdapterURL() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            current.deleteLastPathComponent()
            let candidate = current.appendingPathComponent("tools/codex_acp_adapter.swift", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw AIProviderError.runtimeFailure("Codex ACP adapter script is missing from the workspace.")
    }
}

private struct ACPRequestError: LocalizedError {
    let message: String
    let code: Int?

    var errorDescription: String? { message }

    static func from(_ error: [String: Any]) -> ACPRequestError {
        ACPRequestError(
            message: error["message"] as? String ?? "ACP request failed.",
            code: error["code"] as? Int
        )
    }
}
