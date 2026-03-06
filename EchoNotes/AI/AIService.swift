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
        let chatgptAccountId: String?

        init(apiKey: String, model: String = "gpt-4o-mini", endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!, provider: AIProvider = .openai, chatgptAccountId: String? = nil) {
            self.apiKey = apiKey
            self.model = model
            self.endpoint = endpoint
            self.provider = provider
            self.chatgptAccountId = chatgptAccountId
        }
    }

    /// Summarize a transcript using the configured AI provider.
    func summarize(transcript: String, config: Configuration, knowledgeBaseContext: String? = nil) async throws -> MeetingSummary {
        // Use ChatGPT backend Responses API when we have an account ID but no API key
        if config.chatgptAccountId != nil {
            return try await summarizeChatGPTBackend(transcript: transcript, config: config, knowledgeBaseContext: knowledgeBaseContext)
        }

        switch config.provider {
        case .anthropic:
            return try await summarizeAnthropic(transcript: transcript, config: config, knowledgeBaseContext: knowledgeBaseContext)
        case .google:
            return try await summarizeGoogle(transcript: transcript, config: config, knowledgeBaseContext: knowledgeBaseContext)
        case .ollama:
            return try await summarizeOllama(transcript: transcript, config: config, knowledgeBaseContext: knowledgeBaseContext)
        case .openai, .custom:
            return try await summarizeOpenAICompatible(transcript: transcript, config: config, knowledgeBaseContext: knowledgeBaseContext)
        }
    }

    // MARK: - ChatGPT Backend (Responses API)

    /// Use the ChatGPT backend Responses API with OAuth access token.
    /// Same approach as Codex CLI: Bearer access_token + chatgpt-account-id header.
    /// The Codex backend requires stream: true, so we collect SSE events.
    private func summarizeChatGPTBackend(transcript: String, config: Configuration, knowledgeBaseContext: String? = nil) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript, knowledgeBaseContext: knowledgeBaseContext)
        let systemPrompt = "You are a meeting assistant. Extract structured summaries from transcripts. Respond only with valid JSON."

        let requestBody: [String: Any] = [
            "model": config.model,
            "instructions": systemPrompt,
            "input": [
                ["role": "user", "content": prompt]
            ],
            "store": false,
            "stream": true,
        ]

        let url = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accountId = config.chatgptAccountId {
            request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        // Stream the response and collect text deltas
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            // Read the error body
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let body = String(data: errorData, encoding: .utf8) ?? "unknown"
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        // Parse SSE events to collect the full text output
        var fullText = ""
        for try await line in bytes.lines {
            // SSE format: "data: {...}" or "data: [DONE]"
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let eventData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else { continue }

            // Look for text delta events: response.output_text.delta
            if let type = event["type"] as? String, type == "response.output_text.delta",
               let delta = event["delta"] as? String {
                fullText += delta
            }

            // Also check for response.completed which has the final output_text
            if let type = event["type"] as? String, type == "response.completed",
               let resp = event["response"] as? [String: Any],
               let outputText = resp["output_text"] as? String {
                fullText = outputText
            }
        }

        guard !fullText.isEmpty else {
            throw AIError.invalidResponse
        }

        return try extractSummary(from: fullText)
    }

    /// Parse the OpenAI Responses API format.
    /// Response contains `output_text` (shorthand) and/or `output` array with message items.
    func parseChatGPTResponse(_ data: Data) throws -> MeetingSummary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }

        // Try output_text shorthand first
        var text: String?
        if let outputText = json["output_text"] as? String {
            text = outputText
        }

        // Fall back to parsing the output array
        if text == nil, let output = json["output"] as? [[String: Any]] {
            for item in output {
                guard let type = item["type"] as? String, type == "message",
                      let content = item["content"] as? [[String: Any]] else { continue }
                for block in content {
                    guard let blockType = block["type"] as? String, blockType == "output_text",
                          let blockText = block["text"] as? String else { continue }
                    text = blockText
                    break
                }
                if text != nil { break }
            }
        }

        guard let text else {
            throw AIError.invalidResponse
        }

        return try extractSummary(from: text)
    }

    // MARK: - OpenAI-compatible (OpenAI)

    private func summarizeOpenAICompatible(transcript: String, config: Configuration, knowledgeBaseContext: String? = nil) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript, knowledgeBaseContext: knowledgeBaseContext)
        let isLocal = config.provider == .custom || config.provider == .ollama

        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": "You are a meeting assistant. Extract structured summaries from transcripts. Respond only with valid JSON. Do not include any explanation or thinking, just the JSON object."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": isLocal ? 8192 : 2000
        ]

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        if !config.apiKey.isEmpty {
            request.setValue(config.provider.authHeaderValue(apiKey: config.apiKey), forHTTPHeaderField: config.provider.authHeaderName)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accountId = config.chatgptAccountId {
            request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        // Local models need more time — a 35B model on a long transcript can take minutes
        request.timeoutInterval = isLocal ? 300 : 120

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

    // MARK: - Ollama

    private func summarizeOllama(transcript: String, config: Configuration, knowledgeBaseContext: String? = nil) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript, knowledgeBaseContext: knowledgeBaseContext)

        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": "You are a meeting assistant. Extract structured summaries from transcripts. Respond only with valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "stream": false
        ]

        var request = URLRequest(url: config.endpoint)
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

        return try parseResponse(data)
    }

    // MARK: - Anthropic

    private func summarizeAnthropic(transcript: String, config: Configuration, knowledgeBaseContext: String? = nil) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript, knowledgeBaseContext: knowledgeBaseContext)

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

    private func summarizeGoogle(transcript: String, config: Configuration, knowledgeBaseContext: String? = nil) async throws -> MeetingSummary {
        let prompt = summaryPrompt(transcript: transcript, knowledgeBaseContext: knowledgeBaseContext)

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

    private func summaryPrompt(transcript: String, knowledgeBaseContext: String? = nil) -> String {
        var prompt = """
        Analyze this meeting transcript and provide a structured summary.

        Respond ONLY with valid JSON in this exact format:
        {
          "summary": "A concise paragraph summarizing the meeting",
          "actionItems": ["Action item 1", "Action item 2"],
          "keyDecisions": ["Decision 1", "Decision 2"],
          "openQuestions": ["Question 1", "Question 2"]
        }

        If a section has no items, use an empty array.
        """

        if let context = knowledgeBaseContext {
            prompt += """

            \nUse the following project knowledge base for context. Reference correct terminology, people, and prior decisions where relevant:

            \(context)
            """
        }

        prompt += """

        \nTRANSCRIPT:
        \(transcript)
        """

        return prompt
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

        return try extractSummary(from: content)
    }

    /// Extract MeetingSummary from raw AI text output.
    /// Handles: <think> blocks, markdown fences, extra text around JSON, snake_case keys.
    private func extractSummary(from text: String) throws -> MeetingSummary {
        var cleaned = text

        // Strip <think>...</think> blocks (Qwen, DeepSeek reasoning models)
        while let thinkStart = cleaned.range(of: "<think>"),
              let thinkEnd = cleaned.range(of: "</think>") {
            cleaned.removeSubrange(thinkStart.lowerBound..<thinkEnd.upperBound)
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find JSON object if there's extra text around it
        if !cleaned.hasPrefix("{"), let braceStart = cleaned.firstIndex(of: "{") {
            cleaned = String(cleaned[braceStart...])
        }
        if let braceEnd = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[...braceEnd])
        }

        guard let summaryData = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse
        }

        // Try camelCase first, then snake_case
        let decoder = JSONDecoder()
        if let result = try? decoder.decode(MeetingSummary.self, from: summaryData) {
            return result
        }

        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let result = try? decoder.decode(MeetingSummary.self, from: summaryData) {
            return result
        }

        // Manual fallback: parse JSON dict and extract fields flexibly
        if let dict = try? JSONSerialization.jsonObject(with: summaryData) as? [String: Any] {
            let summary = (dict["summary"] as? String) ?? ""
            let actionItems = (dict["actionItems"] ?? dict["action_items"]) as? [String] ?? []
            let keyDecisions = (dict["keyDecisions"] ?? dict["key_decisions"]) as? [String] ?? []
            let openQuestions = (dict["openQuestions"] ?? dict["open_questions"]) as? [String] ?? []

            if !summary.isEmpty {
                return MeetingSummary(summary: summary, actionItems: actionItems, keyDecisions: keyDecisions, openQuestions: openQuestions)
            }
        }

        throw AIError.parseError(content: String(cleaned.prefix(200)))
    }

    /// Parse Anthropic messages API response.
    func parseAnthropicResponse(_ data: Data) throws -> MeetingSummary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw AIError.invalidResponse
        }

        return try extractSummary(from: text)
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

        return try extractSummary(from: text)
    }
}

enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError(content: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Add one in Settings."
        case .invalidResponse: return "Invalid response from AI service."
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .parseError(let content): return "Could not parse AI response as JSON. Response started with: \(content)"
        }
    }
}
