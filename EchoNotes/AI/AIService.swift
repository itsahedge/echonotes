import Foundation
import os

/// Structured meeting summary from AI.
struct MeetingSummary: Codable, Sendable {
    let summary: String
    let actionItems: [String]
    let keyDecisions: [String]
    let openQuestions: [String]

    /// Export as Markdown.
    func toMarkdown() -> String {
        var md = "# Meeting Summary\n\n\(summary)\n"

        if !actionItems.isEmpty {
            md += "\n## Action Items\n"
            for item in actionItems { md += "- [ ] \(item)\n" }
        }
        if !keyDecisions.isEmpty {
            md += "\n## Key Decisions\n"
            for item in keyDecisions { md += "- \(item)\n" }
        }
        if !openQuestions.isEmpty {
            md += "\n## Open Questions\n"
            for item in openQuestions { md += "- \(item)\n" }
        }
        return md
    }
}

/// Sends transcripts to OpenAI for AI-powered meeting summaries.
final class AIService: Sendable {
    private let logger = Logger(subsystem: "com.echonotes", category: "AIService")

    struct Configuration: Sendable {
        let apiKey: String
        let model: String
        let endpoint: URL
        let provider: AIProvider

        init(apiKey: String, model: String = "gpt-4o-mini", endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!, provider: AIProvider = .openai) {
            self.apiKey = apiKey
            self.model = model
            self.endpoint = endpoint
            self.provider = provider
        }
    }

    /// Summarize a transcript using the configured AI provider.
    func summarize(transcript: String, config: Configuration) async throws -> MeetingSummary {
        switch config.provider {
        case .anthropic:
            return try await summarizeAnthropic(transcript: transcript, config: config)
        case .google:
            return try await summarizeGoogle(transcript: transcript, config: config)
        default:
            // OpenAI-compatible (OpenAI, Ollama)
            return try await summarizeOpenAICompatible(transcript: transcript, config: config)
        }
    }

    // MARK: - OpenAI-compatible (OpenAI, Ollama)

    private func summarizeOpenAICompatible(transcript: String, config: Configuration) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript)

        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": "You are a meeting assistant. Extract structured summaries from transcripts. Respond only with valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]

        // Only add response_format for non-Ollama (some local models don't support it)
        if config.provider != .ollama {
            requestBody["response_format"] = ["type": "json_object"]
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue(config.provider.authHeaderValue(apiKey: config.apiKey), forHTTPHeaderField: config.provider.authHeaderName)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return try parseResponse(data)
    }

    // MARK: - Anthropic

    private func summarizeAnthropic(transcript: String, config: Configuration) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript)

        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": 2000,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "system": "You are a meeting assistant. Extract structured summaries from transcripts. Respond only with valid JSON."
        ]

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return try parseAnthropicResponse(data)
    }

    // MARK: - Google Gemini

    private func summarizeGoogle(transcript: String, config: Configuration) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript)

        let endpointURL = URL(string: "\(config.provider.defaultEndpoint)/\(config.model):generateContent?key=\(config.apiKey)")!

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": "You are a meeting assistant. Extract structured summaries from transcripts. Respond only with valid JSON.\n\n\(prompt)"]]]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 2000,
                "responseMimeType": "application/json"
            ]
        ]

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return try parseGoogleResponse(data)
    }

    // MARK: - Shared Prompt

    private func summaryPrompt(transcript: String) -> String {
        """
        Analyze this meeting transcript and provide a structured summary.

        Respond ONLY with valid JSON in this exact format:
        {
          "summary": "A concise paragraph summarizing the meeting",
          "actionItems": ["Action item 1", "Action item 2"],
          "keyDecisions": ["Decision 1", "Decision 2"],
          "openQuestions": ["Question 1", "Question 2"]
        }

        If a section has no items, use an empty array.

        TRANSCRIPT:
        \(transcript)
        """
    }

    /// Parse OpenAI chat completion response into MeetingSummary.
    func parseResponse(_ data: Data) throws -> MeetingSummary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }

        // Strip markdown code fences if present
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let summaryData = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse
        }

        return try JSONDecoder().decode(MeetingSummary.self, from: summaryData)
    }

    /// Parse Anthropic messages API response.
    func parseAnthropicResponse(_ data: Data) throws -> MeetingSummary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw AIError.invalidResponse
        }

        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let summaryData = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse
        }
        return try JSONDecoder().decode(MeetingSummary.self, from: summaryData)
    }

    /// Parse Google Gemini generateContent response.
    func parseGoogleResponse(_ data: Data) throws -> MeetingSummary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIError.invalidResponse
        }

        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let summaryData = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse
        }
        return try JSONDecoder().decode(MeetingSummary.self, from: summaryData)
    }
}

enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Add one in Settings."
        case .invalidResponse: return "Invalid response from AI service."
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        }
    }
}
