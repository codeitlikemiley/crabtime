import Foundation

struct AIProviderManager {
    let settingsStore: AISettingsStore
    let credentialStore: CredentialStore
    let acpService: ACPTransportService

    init(
        settingsStore: AISettingsStore,
        credentialStore: CredentialStore,
        appPaths: AppStoragePaths = .live()
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
        self.acpService = ACPTransportService(appPaths: appPaths, credentialStore: credentialStore)
    }

    func sendMessage(
        session: ExerciseChatSession,
        messages: [ExerciseChatMessage],
        context: String,
        eventSink: (@Sendable (AITransportEvent) -> Void)? = nil
    ) async throws -> AIProviderReply {
        let selectedTransport = await MainActor.run {
            settingsStore.preference(for: session.providerKind).transport
        }
        let transcript = renderTranscript(messages: messages)
        let prompt = """
        \(context)

        Conversation so far:
        \(transcript)

        Respond to the latest user message as a concise, technically correct tutor. Use markdown when helpful.
        """

        switch session.providerKind {
        case .codexCLI:
            if selectedTransport == .acp {
                return try await sendACPMessage(
                    session: session,
                    messages: messages,
                    context: context,
                    eventSink: eventSink
                )
            }
            return AIProviderReply(
                content: try await runCLI(
                command: "codex",
                arguments: ["exec", "-", "--skip-git-repo-check", "--json", "-m", session.model],
                stdin: Data(prompt.utf8)
            )
            )
        case .geminiCLI:
            if selectedTransport == .acp {
                return try await sendACPMessage(
                    session: session,
                    messages: messages,
                    context: context,
                    eventSink: eventSink
                )
            }
            return AIProviderReply(
                content: try await runCLI(command: "gemini", arguments: ["-p", prompt, "-m", session.model])
            )
        case .claudeCLI:
            return AIProviderReply(
                content: try await runCLI(command: "claude", arguments: ["-p", prompt, "--output-format", "text", "--model", session.model])
            )
        case .openCodeCLI:
            if selectedTransport == .acp {
                return try await sendACPMessage(
                    session: session,
                    messages: messages,
                    context: context,
                    eventSink: eventSink
                )
            }
            return AIProviderReply(
                content: try await runCLI(command: "opencode", arguments: ["run", prompt, "-m", session.model])
            )
        case .openAI:
            let result = try await sendOpenAICompatibleMessage(
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                apiKey: try apiKey(for: .openAI),
                model: session.model,
                systemPrompt: context,
                messages: messages,
                isOpenRouter: false
            )
            return AIProviderReply(content: result.content, thinkingContent: result.thinking)
        case .openRouter:
            let result = try await sendOpenAICompatibleMessage(
                endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                apiKey: try apiKey(for: .openRouter),
                model: session.model,
                systemPrompt: context,
                messages: messages,
                isOpenRouter: true
            )
            return AIProviderReply(content: result.content, thinkingContent: result.thinking)
        case .groq:
            let result = try await sendOpenAICompatibleMessage(
                endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                apiKey: try apiKey(for: .groq),
                model: session.model,
                systemPrompt: context,
                messages: messages,
                isOpenRouter: false
            )
            return AIProviderReply(content: result.content, thinkingContent: result.thinking)
        case .nexum:
            let result = try await sendOpenAICompatibleMessage(
                endpoint: URL(string: "https://www.dialagram.me/router/v1/chat/completions")!,
                apiKey: try apiKey(for: .nexum),
                model: session.model,
                systemPrompt: context,
                messages: messages,
                isOpenRouter: false
            )
            return AIProviderReply(content: result.content, thinkingContent: result.thinking)
        case .anthropic:
            return AIProviderReply(
                content: try await sendAnthropicMessage(
                apiKey: try apiKey(for: .anthropic),
                model: session.model,
                systemPrompt: context,
                messages: messages
            )
            )
        case .geminiAPI:
            return AIProviderReply(
                content: try await sendGeminiAPIMessage(
                apiKey: try apiKey(for: .geminiAPI),
                model: session.model,
                prompt: prompt
            )
            )
        }
    }

    @MainActor
    func generate(systemPrompt: String, userMessage: String, workspaceRootPath: String) async throws -> String {
        let provider = settingsStore.defaultProvider
        let model = settingsStore.preference(for: provider).model

        let session = ExerciseChatSession(
            workspaceRootPath: workspaceRootPath,
            exercisePath: workspaceRootPath,
            title: "generation",
            providerKind: provider,
            model: model
        )

        let message = ExerciseChatMessage(
            sessionID: session.id,
            role: .user,
            content: userMessage
        )

        return try await sendMessage(
            session: session,
            messages: [message],
            context: systemPrompt
        ).content
    }

    @MainActor
    func displayModel(for kind: AIProviderKind) -> String {
        settingsStore.preference(for: kind).model
    }

    @MainActor
    func transport(for kind: AIProviderKind) -> AITransportKind {
        settingsStore.preference(for: kind).transport
    }

    func restartACPConnection(
        session: ExerciseChatSession,
        eventSink: (@Sendable (AITransportEvent) -> Void)? = nil
    ) async {
        let isACP = await MainActor.run {
            settingsStore.preference(for: session.providerKind).transport == .acp
        }
        guard isACP else {
            return
        }

        await acpService.restartConnection(
            provider: session.providerKind,
            model: session.model,
            workspaceRootPath: session.workspaceRootPath,
            eventSink: eventSink
        )
    }

    func shutdownProvider(
        _ provider: AIProviderKind,
        reason: String,
        eventSink: (@Sendable (AITransportEvent) -> Void)? = nil
    ) async {
        await acpService.shutdownConnectionsForProvider(
            provider,
            reason: reason,
            eventSink: eventSink
        )
    }

    private func apiKey(for kind: AIProviderKind) throws -> String {
        guard let apiKey = credentialStore.readSecret(for: kind.credentialKey), !apiKey.isEmpty else {
            throw AIProviderError.missingCredential(kind.title)
        }
        return apiKey
    }

    private func renderTranscript(messages: [ExerciseChatMessage]) -> String {
        messages.map { message in
            "\(message.role.rawValue.uppercased()):\n\(message.content)"
        }.joined(separator: "\n\n")
    }

    private func runCLI(command: String, arguments: [String], stdin: Data? = nil) async throws -> String {
        guard ToolingHealthService.resolveExecutable(named: command) != nil else {
            throw AIProviderError.missingExecutable(command)
        }

        let result = try await ToolingHealthService.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [command] + arguments,
            currentDirectoryURL: nil,
            stdin: stdin
        )

        guard result.terminationStatus == 0 else {
            throw AIProviderError.runtimeFailure(result.combinedText)
        }

        let output: String
        if command == "codex" {
            output = parseCodexJSONOutput(result.stdout)
        } else {
            output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !output.isEmpty else {
            let fallback = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallback.isEmpty else {
                throw AIProviderError.emptyResponse(command)
            }
            return fallback
        }
        return output
    }

    private func sendACPMessage(
        session: ExerciseChatSession,
        messages: [ExerciseChatMessage],
        context: String,
        eventSink: (@Sendable (AITransportEvent) -> Void)?
    ) async throws -> AIProviderReply {
        let prompt = renderACPPrompt(
            session: session,
            messages: messages,
            context: context
        )

        return try await acpService.sendMessage(
            provider: session.providerKind,
            model: session.model,
            workspaceRootPath: session.workspaceRootPath,
            existingSessionID: session.backendSessionID,
            prompt: prompt,
            eventSink: eventSink
        )
    }

    private struct OpenAICompatibleResult {
        let content: String
        let thinking: String?
    }

    private func sendOpenAICompatibleMessage(
        endpoint: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [ExerciseChatMessage],
        isOpenRouter: Bool
    ) async throws -> OpenAICompatibleResult {
        struct RequestBody: Encodable {
            struct ChatMessage: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let messages: [ChatMessage]
            let stream: Bool
        }

        // content can be null when a thinking model puts all its text in reasoning_content
        struct ResponseChoice: Decodable {
            struct ChatMessage: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let message: ChatMessage
        }
        struct ResponseBody: Decodable {
            let choices: [ResponseChoice]
        }

        let allMessages = [RequestBody.ChatMessage(role: "system", content: systemPrompt)] + messages.map {
            RequestBody.ChatMessage(role: $0.role == .assistant ? "assistant" : "user", content: $0.content)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if isOpenRouter {
            request.addValue(AppBrand.bundleIdentifier, forHTTPHeaderField: "HTTP-Referer")
            request.addValue(AppBrand.shortName, forHTTPHeaderField: "X-Title")
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, messages: allMessages, stream: false))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let choice = decoded.choices.first else {
            throw AIProviderError.emptyResponse(endpoint.absoluteString)
        }

        // Combine content fields — some providers (Nexum/Qwen) return null content
        // with the actual reply in reasoning_content when in thinking mode.
        let rawText = [choice.message.content, choice.message.reasoning_content]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !rawText.isEmpty else {
            throw AIProviderError.emptyResponse(endpoint.absoluteString)
        }

        let extracted = Self.extractThinkingBlock(from: rawText)
        return OpenAICompatibleResult(content: extracted.content, thinking: extracted.thinking)
    }

    /// Strips one leading `<think>…</think>` block from a model response.
    /// Returns the extracted thinking and the cleaned visible text.
    /// Works for Qwen3, DeepSeek-R1, and any similar model.
    private static func extractThinkingBlock(from raw: String) -> (content: String, thinking: String?) {
        let thinkOpen = "<think>"
        let thinkClose = "</think>"

        guard let openRange = raw.range(of: thinkOpen),
              let closeRange = raw.range(of: thinkClose, range: openRange.upperBound..<raw.endIndex)
        else {
            return (raw.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let thinkingText = String(raw[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleText = String(raw[closeRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let thinking = thinkingText.isEmpty ? nil : thinkingText
        let content = visibleText.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : visibleText
        return (content, thinking)
    }

    private func sendAnthropicMessage(
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [ExerciseChatMessage]
    ) async throws -> String {
        struct RequestBody: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Message]
        }

        struct ResponseBody: Decodable {
            struct ContentPart: Decodable {
                let type: String
                let text: String?
            }
            let content: [ContentPart]
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: model,
                max_tokens: 1400,
                system: systemPrompt,
                messages: messages.map { .init(role: $0.role == .assistant ? "assistant" : "user", content: $0.content) }
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n")
        guard !text.isEmpty else {
            throw AIProviderError.emptyResponse("Anthropic")
        }
        return text
    }

    private func sendGeminiAPIMessage(
        apiKey: String,
        model: String,
        prompt: String
    ) async throws -> String {
        struct RequestBody: Encodable {
            struct Content: Encodable {
                struct Part: Encodable {
                    let text: String
                }
                let parts: [Part]
            }
            let contents: [Content]
        }

        struct ResponseBody: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AIProviderError.runtimeFailure("Malformed Gemini API URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(contents: [.init(parts: [.init(text: prompt)])])
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.candidates?
            .flatMap { $0.content.parts }
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""

        guard !text.isEmpty else {
            throw AIProviderError.emptyResponse("Gemini API")
        }
        return text
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIProviderError.runtimeFailure(message)
        }
    }

    private func parseCodexJSONOutput(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline)
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = object["item"] as? [String: Any],
                  let text = item["text"] as? String
            else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderACPPrompt(
        session: ExerciseChatSession,
        messages: [ExerciseChatMessage],
        context: String
    ) -> String {
        let latestUserMessage = messages.last(where: { $0.role == .user })?.content ?? ""

        if session.backendSessionID == nil {
            return """
            \(context)

            Conversation so far:
            \(renderTranscript(messages: messages))

            Respond to the latest user message as a concise, technically correct tutor. Use markdown when helpful.
            """
        }

        return """
        \(context)

        Latest user message:
        \(latestUserMessage)

        Use the session history you already have. Respond as a concise, technically correct tutor. Use markdown when helpful.
        """
    }
}

enum AIProviderError: LocalizedError {
    case missingExecutable(String)
    case missingCredential(String)
    case runtimeFailure(String)
    case emptyResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let command):
            "\(command) is not installed or not available in PATH."
        case .missingCredential(let provider):
            "\(provider) is missing credentials. Add them in Settings."
        case .runtimeFailure(let message):
            message
        case .emptyResponse(let provider):
            "\(provider) returned an empty response."
        }
    }
}
