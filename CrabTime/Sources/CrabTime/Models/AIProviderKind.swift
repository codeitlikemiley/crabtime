import Foundation

enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case codexCLI
    case geminiCLI
    case claudeCLI
    case openCodeCLI
    case openAI
    case anthropic
    case geminiAPI
    case openRouter
    case groq
    case nexum
    case xai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codexCLI:
            "Codex CLI"
        case .geminiCLI:
            "Gemini CLI"
        case .claudeCLI:
            "Claude Code"
        case .openCodeCLI:
            "OpenCode"
        case .openAI:
            "OpenAI API"
        case .anthropic:
            "Anthropic API"
        case .geminiAPI:
            "Gemini API"
        case .openRouter:
            "OpenRouter"
        case .groq:
            "Groq API"
        case .nexum:
            "Nexum Router"
        case .xai:
            "xAI Grok"
        }
    }

    var shortTitle: String {
        switch self {
        case .codexCLI:
            "Codex"
        case .geminiCLI, .geminiAPI:
            "Gemini"
        case .claudeCLI:
            "Claude"
        case .openCodeCLI:
            "OpenCode"
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .openRouter:
            "OpenRouter"
        case .groq:
            "Groq"
        case .nexum:
            "Nexum"
        case .xai:
            "Grok"
        }
    }

    var systemImage: String {
        switch self {
        case .codexCLI:
            "sparkles.rectangle.stack"
        case .geminiCLI, .geminiAPI:
            "diamond"
        case .claudeCLI:
            "brain"
        case .openCodeCLI:
            "terminal"
        case .openAI:
            "bolt.horizontal.circle"
        case .anthropic:
            "person.text.rectangle"
        case .openRouter:
            "network"
        case .groq:
            "hare.fill"
        case .nexum:
            "server.rack"
        case .xai:
            "bolt.fill"
        }
    }

    var isCLI: Bool {
        switch self {
        case .codexCLI, .geminiCLI, .claudeCLI, .openCodeCLI:
            true
        case .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            false
        }
    }

    var supportsACPTransport: Bool {
        switch self {
        case .codexCLI, .geminiCLI, .openCodeCLI:
            true
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            false
        }
    }

    var defaultTransport: AITransportKind {
        switch self {
        case .geminiCLI, .openCodeCLI:
            .acp
        case .codexCLI, .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            .legacyCLI
        }
    }

    var acpExecutableName: String? {
        switch self {
        case .codexCLI:
            "codex"
        case .geminiCLI:
            "gemini"
        case .openCodeCLI:
            "opencode"
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            nil
        }
    }

    var acpHint: String? {
        switch self {
        case .codexCLI:
            "Uses \(AppBrand.shortName)'s local ACP adapter on top of `codex exec` to keep a warm session inside the app."
        case .geminiCLI:
            "Uses `gemini --acp` so the first startup is cold and later turns reuse the same session."
        case .openCodeCLI:
            "Uses `opencode acp` so the first startup is cold and later turns reuse the same session."
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            nil
        }
    }

    var executableName: String? {
        switch self {
        case .codexCLI:
            "codex"
        case .geminiCLI:
            "gemini"
        case .claudeCLI:
            "claude"
        case .openCodeCLI:
            "opencode"
        case .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai:
            nil
        }
    }

    var installHint: String? {
        switch self {
        case .codexCLI:
            "Install Codex CLI and authenticate with your ChatGPT subscription."
        case .geminiCLI:
            "Install Gemini CLI, then sign in with OAuth or configure an API key."
        case .claudeCLI:
            "Install Claude Code and run `claude setup-token` or sign in with your subscription."
        case .openCodeCLI:
            "Install OpenCode and authenticate one of its configured providers."
        case .openAI:
            "Add an OpenAI API key in Settings."
        case .anthropic:
            "Add an Anthropic API key in Settings."
        case .geminiAPI:
            "Add a Gemini Developer API key in Settings."
        case .openRouter:
            "Add an OpenRouter API key in Settings."
        case .groq:
            "Add a Groq API key in Settings. Get one free at console.groq.com."
        case .nexum:
            "Add a Nexum Router API key in Settings. Generate one at dialagram.me/router."
        case .xai:
            "Add an xAI API key in Settings. Get one at console.x.ai."
        }
    }

    var defaultModel: String {
        switch self {
        case .codexCLI:
            "gpt-5.4"
        case .geminiCLI, .geminiAPI:
            "gemini-2.5-pro"
        case .claudeCLI:
            "sonnet"
        case .openCodeCLI:
            "openai/gpt-5"
        case .openAI:
            "gpt-5"
        case .anthropic:
            "claude-sonnet-4-5"
        case .openRouter:
            "openai/gpt-5"
        case .groq:
            "llama-3.3-70b-versatile"
        case .nexum:
            "qwen-3.6-plus"
        case .xai:
            "grok-4"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .codexCLI:
            [
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.3-codex",
                "gpt-5.2"
            ]
        case .geminiCLI, .geminiAPI:
            [
                "gemini-3.1-pro-preview",
                "gemini-3-flash-preview",
                "gemini-3.1-flash-lite-preview",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite"
            ]
        case .claudeCLI:
            [
                "sonnet",
                "opus",
                "haiku"
            ]
        case .openCodeCLI:
            [
                "opencode/big-pickle",
                "opencode/gpt-5-nano",
                "opencode/minimax-m2.5-free",
                "opencode/nemotron-3-super-free",
                "opencode-go/glm-5",
                "opencode-go/glm-5.1",
                "opencode-go/kimi-k2.5",
                "opencode-go/mimo-v2-omni",
                "opencode-go/mimo-v2-pro",
                "opencode-go/minimax-m2.5",
                "opencode-go/minimax-m2.7"
            ]
        case .openAI:
            [
                "gpt-5",
                "gpt-5-mini",
                "gpt-5.4",
                "gpt-5.4-mini"
            ]
        case .anthropic:
            [
                "claude-sonnet-4-5",
                "claude-opus-4-1",
                "claude-haiku-4"
            ]
        case .openRouter:
            [
                "openai/gpt-5",
                "openai/gpt-5-mini",
                "anthropic/claude-sonnet-4.5",
                "google/gemini-2.5-pro"
            ]
        case .groq:
            [
                "llama-3.3-70b-versatile",
                "llama-3.1-8b-instant",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
                "qwen/qwen3-32b",
                "meta-llama/llama-4-scout-17b-16e-instruct"
            ]
        case .nexum:
            [
                "qwen-3.6-plus",
                "qwen-3.6-plus-thinking",
                "qwen-3.5-plus",
                "qwen-3.5-plus-thinking"
            ]
        case .xai:
            [
                "grok-4.20",
                "grok-4",
                "grok-3",
                "grok-3-mini"
            ]
        }
    }

    var credentialKey: String {
        "ai-provider-\(rawValue)"
    }

    static var defaultChatProviders: [AIProviderKind] {
        [.codexCLI, .geminiCLI, .claudeCLI, .openCodeCLI, .openAI, .anthropic, .geminiAPI, .openRouter, .groq, .nexum, .xai]
    }
}
