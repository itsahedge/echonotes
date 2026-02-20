import Testing
import Foundation
@testable import EchoNotes

@Suite("AIProvider")
struct AIProviderTests {

    @Test("All providers have a display name")
    func displayNames() {
        for provider in AIProvider.allCases {
            #expect(!provider.displayName.isEmpty)
        }
    }

    @Test("All providers have a default model")
    func defaultModels() {
        for provider in AIProvider.allCases {
            #expect(!provider.defaultModel.isEmpty)
        }
    }

    @Test("All providers have at least one model option")
    func modelOptions() {
        for provider in AIProvider.allCases {
            #expect(!provider.modelOptions.isEmpty)
            #expect(provider.modelOptions.contains(provider.defaultModel))
        }
    }

    @Test("All providers have a default endpoint")
    func endpoints() {
        for provider in AIProvider.allCases {
            let url = URL(string: provider.defaultEndpoint)
            #expect(url != nil, "Invalid endpoint URL for \(provider.displayName)")
        }
    }

    @Test("Only Ollama doesn't require an API key")
    func apiKeyRequirements() {
        #expect(AIProvider.openai.requiresAPIKey)
        #expect(AIProvider.anthropic.requiresAPIKey)
        #expect(AIProvider.google.requiresAPIKey)
        #expect(!AIProvider.ollama.requiresAPIKey)
    }

    @Test("OpenAI uses Bearer auth")
    func openaiAuth() {
        let provider = AIProvider.openai
        #expect(provider.authHeaderName == "Authorization")
        #expect(provider.authHeaderValue(apiKey: "test-key") == "Bearer test-key")
    }

    @Test("Anthropic uses x-api-key header")
    func anthropicAuth() {
        let provider = AIProvider.anthropic
        #expect(provider.authHeaderName == "x-api-key")
        #expect(provider.authHeaderValue(apiKey: "sk-ant-123") == "sk-ant-123")
    }

    @Test("Provider raw values are stable for persistence")
    func rawValues() {
        #expect(AIProvider.openai.rawValue == "OpenAI")
        #expect(AIProvider.anthropic.rawValue == "Anthropic")
        #expect(AIProvider.google.rawValue == "Google Gemini")
        #expect(AIProvider.ollama.rawValue == "Ollama (Local)")
    }

    @Test("Provider JSON round-trip")
    func jsonRoundTrip() throws {
        for provider in AIProvider.allCases {
            let encoded = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(AIProvider.self, from: encoded)
            #expect(decoded == provider)
        }
    }

    @Test("AIService.Configuration includes provider")
    func configWithProvider() {
        let config = AIService.Configuration(
            apiKey: "test",
            model: "claude-sonnet-4-5",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            provider: .anthropic
        )
        #expect(config.provider == .anthropic)
        #expect(config.model == "claude-sonnet-4-5")
    }

    // MARK: - Response Parsing

    @Test("parseAnthropicResponse handles valid response")
    func parseAnthropic() throws {
        let service = AIService()
        let json: [String: Any] = [
            "content": [
                ["type": "text", "text": """
                {"summary":"Team sync","actionItems":["Ship it"],"keyDecisions":["Use Swift"],"openQuestions":[]}
                """]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try service.parseAnthropicResponse(data)
        #expect(result.summary == "Team sync")
        #expect(result.actionItems == ["Ship it"])
    }

    @Test("parseGoogleResponse handles valid response")
    func parseGoogle() throws {
        let service = AIService()
        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [
                        ["text": """
                        {"summary":"Quick chat","actionItems":[],"keyDecisions":["Go with plan B"],"openQuestions":["Timeline?"]}
                        """]
                    ]
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try service.parseGoogleResponse(data)
        #expect(result.summary == "Quick chat")
        #expect(result.keyDecisions == ["Go with plan B"])
    }

    @Test("parseAnthropicResponse throws on empty content")
    func parseAnthropicEmpty() {
        let service = AIService()
        let json: [String: Any] = ["content": []]
        let data = try! JSONSerialization.data(withJSONObject: json)
        #expect(throws: AIError.self) {
            try service.parseAnthropicResponse(data)
        }
    }

    @Test("parseGoogleResponse throws on empty candidates")
    func parseGoogleEmpty() {
        let service = AIService()
        let json: [String: Any] = ["candidates": []]
        let data = try! JSONSerialization.data(withJSONObject: json)
        #expect(throws: AIError.self) {
            try service.parseGoogleResponse(data)
        }
    }
}
