import Testing
import Foundation
@testable import EchoNotes

@Suite("AIService")
struct AIServiceTests {

    let service = AIService()

    // MARK: - parseResponse

    @Test("parseResponse handles valid OpenAI response")
    func parseValidResponse() throws {
        let json: [String: Any] = [
            "choices": [[
                "message": [
                    "content": """
                    {"summary":"Team discussed roadmap","actionItems":["Ship v2"],"keyDecisions":["Use Swift"],"openQuestions":["Timeline?"]}
                    """
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try service.parseResponse(data)
        #expect(result.summary == "Team discussed roadmap")
        #expect(result.actionItems == ["Ship v2"])
        #expect(result.keyDecisions == ["Use Swift"])
        #expect(result.openQuestions == ["Timeline?"])
    }

    @Test("parseResponse strips markdown code fences")
    func parseWithCodeFences() throws {
        let json: [String: Any] = [
            "choices": [[
                "message": [
                    "content": """
                    ```json
                    {"summary":"Test","actionItems":[],"keyDecisions":[],"openQuestions":[]}
                    ```
                    """
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try service.parseResponse(data)
        #expect(result.summary == "Test")
    }

    @Test("parseResponse strips plain code fences without json tag")
    func parseWithPlainCodeFences() throws {
        let json: [String: Any] = [
            "choices": [[
                "message": [
                    "content": """
                    ```
                    {"summary":"Plain","actionItems":[],"keyDecisions":[],"openQuestions":[]}
                    ```
                    """
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try service.parseResponse(data)
        #expect(result.summary == "Plain")
    }

    @Test("parseResponse handles empty arrays")
    func parseEmptyArrays() throws {
        let json: [String: Any] = [
            "choices": [[
                "message": [
                    "content": """
                    {"summary":"Nothing happened","actionItems":[],"keyDecisions":[],"openQuestions":[]}
                    """
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try service.parseResponse(data)
        #expect(result.actionItems.isEmpty)
        #expect(result.keyDecisions.isEmpty)
        #expect(result.openQuestions.isEmpty)
    }

    @Test("parseResponse throws on missing choices")
    func parseMissingChoices() {
        let json: [String: Any] = ["id": "test"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        #expect(throws: AIError.self) {
            try service.parseResponse(data)
        }
    }

    @Test("parseResponse throws on empty choices")
    func parseEmptyChoices() {
        let json: [String: Any] = ["choices": []]
        let data = try! JSONSerialization.data(withJSONObject: json) as Data
        #expect(throws: AIError.self) {
            try service.parseResponse(data)
        }
    }

    @Test("parseResponse throws on malformed JSON content")
    func parseMalformedContent() {
        let json: [String: Any] = [
            "choices": [[
                "message": ["content": "this is not json at all"]
            ]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) {
            try service.parseResponse(data)
        }
    }

    @Test("parseResponse throws on missing required fields")
    func parseMissingFields() {
        let json: [String: Any] = [
            "choices": [[
                "message": ["content": """
                    {"summary":"Only summary"}
                """]
            ]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) {
            try service.parseResponse(data)
        }
    }

    // MARK: - MeetingSummary.toMarkdown

    @Test("toMarkdown includes all sections")
    func toMarkdownFull() {
        let summary = MeetingSummary(
            summary: "Discussed roadmap",
            actionItems: ["Ship v2", "Write docs"],
            keyDecisions: ["Use Swift"],
            openQuestions: ["When to launch?"]
        )
        let md = summary.toMarkdown()
        #expect(md.contains("# Meeting Summary"))
        #expect(md.contains("Discussed roadmap"))
        #expect(md.contains("## Action Items"))
        #expect(md.contains("- [ ] Ship v2"))
        #expect(md.contains("- [ ] Write docs"))
        #expect(md.contains("## Key Decisions"))
        #expect(md.contains("- Use Swift"))
        #expect(md.contains("## Open Questions"))
        #expect(md.contains("- When to launch?"))
    }

    @Test("toMarkdown omits empty sections")
    func toMarkdownEmpty() {
        let summary = MeetingSummary(
            summary: "Quick chat",
            actionItems: [],
            keyDecisions: [],
            openQuestions: []
        )
        let md = summary.toMarkdown()
        #expect(md.contains("Quick chat"))
        #expect(!md.contains("## Action Items"))
        #expect(!md.contains("## Key Decisions"))
        #expect(!md.contains("## Open Questions"))
    }

    @Test("toMarkdown action items use task list format")
    func toMarkdownTaskList() {
        let summary = MeetingSummary(
            summary: "Test",
            actionItems: ["Do thing"],
            keyDecisions: [],
            openQuestions: []
        )
        let md = summary.toMarkdown()
        #expect(md.contains("- [ ] Do thing"))
    }

    // MARK: - MeetingSummary Persistence

    @Test("MeetingSummary JSON round-trip preserves all fields")
    func summaryJSONRoundTrip() throws {
        let original = MeetingSummary(
            summary: "Discussed Q1 goals",
            actionItems: ["Ship feature A", "Hire designer"],
            keyDecisions: ["Use SwiftUI", "Monthly releases"],
            openQuestions: ["Budget for Q2?"]
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MeetingSummary.self, from: encoded)
        #expect(decoded.summary == original.summary)
        #expect(decoded.actionItems == original.actionItems)
        #expect(decoded.keyDecisions == original.keyDecisions)
        #expect(decoded.openQuestions == original.openQuestions)
    }

    @Test("MeetingSummary JSON round-trip with empty arrays")
    func summaryJSONRoundTripEmpty() throws {
        let original = MeetingSummary(
            summary: "Brief chat",
            actionItems: [],
            keyDecisions: [],
            openQuestions: []
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MeetingSummary.self, from: encoded)
        #expect(decoded.summary == "Brief chat")
        #expect(decoded.actionItems.isEmpty)
    }

    // MARK: - AIError

    @Test("AIError descriptions are user-friendly")
    func errorDescriptions() {
        #expect(AIError.noAPIKey.localizedDescription.contains("API key"))
        #expect(AIError.invalidResponse.localizedDescription.contains("Invalid"))
        #expect(AIError.apiError(statusCode: 429, message: "rate limit").localizedDescription.contains("429"))
    }
}
