import Foundation

/// Generates structured meeting notes from transcripts using the OpenAI API.
enum MeetingNotesGenerator {
    private static let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let model = "gpt-4o"

    private static let systemPrompt = """
        You are a meeting notes assistant. Given a transcript, extract:
        1) Summary (2-3 sentences)
        2) Key decisions made
        3) Action items (who, what)
        4) Open questions

        Respond ONLY with valid JSON in this exact format:
        {
          "summary": "...",
          "keyDecisions": ["..."],
          "actionItems": [{"text": "...", "assignee": "..."}],
          "openQuestions": ["..."]
        }
        If a field has no items, use an empty array. For action items with no clear assignee, use null for assignee.
        """

    /// Generate meeting notes from a transcript.
    static func generateNotes(transcript: Transcript, accessToken: String) async throws -> MeetingNotes {
        let userMessage = transcript.toTimestampedText()
        return try await callChatAPI(userMessage: userMessage, accessToken: accessToken)
    }

    // MARK: - Private

    private static func callChatAPI(userMessage: String, accessToken: String) async throws -> MeetingNotes {
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3
        ]

        return try await performRequest(body: body, accessToken: accessToken)
    }

    private static func performRequest(body: [String: Any], accessToken: String) async throws -> MeetingNotes {
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NotesError.apiFailed(statusCode)
        }

        // Parse the chat completion response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NotesError.parseFailed
        }

        // The content should be JSON — parse it into MeetingNotes
        guard let contentData = content.data(using: .utf8) else {
            throw NotesError.parseFailed
        }

        let decoder = JSONDecoder()
        return try decoder.decode(MeetingNotes.self, from: contentData)
    }
}

enum NotesError: LocalizedError {
    case apiFailed(Int)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .apiFailed(let code): return "OpenAI API request failed (HTTP \(code))."
        case .parseFailed: return "Failed to parse meeting notes from API response."
        }
    }
}
