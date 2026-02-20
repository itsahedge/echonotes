import Foundation

/// Supported AI providers for meeting summarization.
enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google Gemini"
    case ollama = "Ollama (Local)"

    var id: String { rawValue }

    /// Display name shown in the UI.
    var displayName: String { rawValue }

    /// Placeholder text for the API key field.
    var apiKeyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .google: return "AIza..."
        case .ollama: return "No API key needed"
        }
    }

    /// Whether this provider requires an API key.
    var requiresAPIKey: Bool {
        self != .ollama
    }

    /// Default API endpoint.
    var defaultEndpoint: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .google: return "https://generativelanguage.googleapis.com/v1beta/models"
        case .ollama: return "http://localhost:11434/v1/chat/completions"
        }
    }

    /// Default model for this provider.
    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-5"
        case .google: return "gemini-2.0-flash"
        case .ollama: return "llama3.2"
        }
    }

    /// Available model options for the provider.
    var modelOptions: [String] {
        switch self {
        case .openai: return ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"]
        case .anthropic: return ["claude-sonnet-4-5", "claude-haiku-3-5"]
        case .google: return ["gemini-2.0-flash", "gemini-2.5-pro"]
        case .ollama: return ["llama3.2", "llama3.1", "mistral", "gemma2"]
        }
    }

    /// How the API key is sent in the request.
    var authHeaderName: String {
        switch self {
        case .anthropic: return "x-api-key"
        default: return "Authorization"
        }
    }

    /// Format the auth header value.
    func authHeaderValue(apiKey: String) -> String {
        switch self {
        case .anthropic: return apiKey
        default: return "Bearer \(apiKey)"
        }
    }
}
