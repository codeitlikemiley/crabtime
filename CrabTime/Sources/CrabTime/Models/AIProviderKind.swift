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
        }
    }

    var isCLI: Bool {
        switch self {
        case .codexCLI, .geminiCLI, .claudeCLI, .openCodeCLI:
            true
        case .openAI, .anthropic, .geminiAPI, .openRouter:
            false
        }
    }

    var supportsACPTransport: Bool {
        switch self {
        case .codexCLI, .geminiCLI, .openCodeCLI:
            true
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter:
            false
        }
    }

    var defaultTransport: AITransportKind {
        switch self {
        case .geminiCLI, .openCodeCLI:
            .acp
        case .codexCLI, .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter:
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
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter:
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
        case .claudeCLI, .openAI, .anthropic, .geminiAPI, .openRouter:
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
        case .openAI, .anthropic, .geminiAPI, .openRouter:
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
        }
    }

    var credentialKey: String {
        "ai-provider-\(rawValue)"
    }

    static var defaultChatProviders: [AIProviderKind] {
        [.codexCLI, .geminiCLI, .claudeCLI, .openCodeCLI, .openAI, .anthropic, .geminiAPI, .openRouter]
    }
}
