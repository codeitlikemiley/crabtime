import Foundation

struct AIProviderManager {
    let settingsStore: AISettingsStore
    let credentialStore: CredentialStore

    func sendMessage(
        session: ExerciseChatSession,
        messages: [ExerciseChatMessage],
        context: String
    ) async throws -> String {
        let transcript = renderTranscript(messages: messages)
        let prompt = """
        \(context)

        Conversation so far:
        \(transcript)

        Respond to the latest user message as a concise, technically correct tutor. Use markdown when helpful.
        """

        switch session.providerKind {
        case .codexCLI:
            return try await runCLI(
                command: "codex",
                arguments: ["exec", "-", "--skip-git-repo-check", "--json", "-m", session.model],
                stdin: Data(prompt.utf8)
            )
        case .geminiCLI:
            return try await runCLI(command: "gemini", arguments: ["-p", prompt, "-m", session.model])
        case .claudeCLI:
            return try await runCLI(command: "claude", arguments: ["-p", prompt, "--output-format", "text", "--model", session.model])
        case .openCodeCLI:
            return try await runCLI(command: "opencode", arguments: ["run", prompt, "-m", session.model])
        case .openAI:
            return try await sendOpenAICompatibleMessage(
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                apiKey: try apiKey(for: .openAI),
                model: session.model,
                systemPrompt: context,
                messages: messages,
                isOpenRouter: false
            )
        case .openRouter:
            return try await sendOpenAICompatibleMessage(
                endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                apiKey: try apiKey(for: .openRouter),
                model: session.model,
                systemPrompt: context,
                messages: messages,
                isOpenRouter: true
            )
        case .anthropic:
            return try await sendAnthropicMessage(
                apiKey: try apiKey(for: .anthropic),
                model: session.model,
                systemPrompt: context,
                messages: messages
            )
        case .geminiAPI:
            return try await sendGeminiAPIMessage(
                apiKey: try apiKey(for: .geminiAPI),
                model: session.model,
                prompt: prompt
            )
        }
    }

    @MainActor
    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        let provider = settingsStore.defaultProvider
        let model = settingsStore.preference(for: provider).model

        let session = ExerciseChatSession(
            workspaceRootPath: "",
            exercisePath: "",
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
        )
    }

    @MainActor
    func displayModel(for kind: AIProviderKind) -> String {
        settingsStore.preference(for: kind).model
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

    private func sendOpenAICompatibleMessage(
        endpoint: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [ExerciseChatMessage],
        isOpenRouter: Bool
    ) async throws -> String {
        struct RequestBody: Encodable {
            struct ChatMessage: Encodable {
                let role: String
                let content: String
            }

            let model: String
            let messages: [ChatMessage]
        }

        struct ResponseBody: Decodable {
            struct Choice: Decodable {
                struct ChatMessage: Decodable {
                    let content: String
                }
                let message: ChatMessage
            }
            let choices: [Choice]
        }

        let allMessages = [RequestBody.ChatMessage(role: "system", content: systemPrompt)] + messages.map {
            RequestBody.ChatMessage(role: $0.role == .assistant ? "assistant" : "user", content: $0.content)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if isOpenRouter {
            request.addValue("RustGoblin", forHTTPHeaderField: "HTTP-Referer")
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, messages: allMessages))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw AIProviderError.emptyResponse(endpoint.absoluteString)
        }
        return content
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

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
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
