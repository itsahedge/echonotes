import Testing
import Foundation
@testable import EchoNotes

@Suite("MeetingNotes")
struct MeetingNotesTests {
    let sampleNotes = MeetingNotes(
        summary: "The team discussed Q1 goals and assigned tasks. Everyone agreed on the timeline.",
        keyDecisions: ["Launch date set to March 15", "Use Swift for the backend"],
        actionItems: [
            ActionItem(text: "Write design doc", assignee: "Alice"),
            ActionItem(text: "Set up CI pipeline", assignee: nil)
        ],
        openQuestions: ["Should we support Linux?", "What about i18n?"]
    )

    @Test("Markdown includes all sections")
    func markdownOutput() {
        let md = sampleNotes.toMarkdown()
        #expect(md.contains("# Meeting Notes"))
        #expect(md.contains("## Summary"))
        #expect(md.contains("Q1 goals"))
        #expect(md.contains("## Key Decisions"))
        #expect(md.contains("- Launch date set to March 15"))
        #expect(md.contains("## Action Items"))
        #expect(md.contains("**Alice:** Write design doc"))
        #expect(md.contains("- Set up CI pipeline"))
        #expect(md.contains("## Open Questions"))
        #expect(md.contains("- Should we support Linux?"))
    }

    @Test("Markdown omits empty sections")
    func markdownEmptySections() {
        let notes = MeetingNotes(
            summary: "Short meeting.",
            keyDecisions: [],
            actionItems: [],
            openQuestions: []
        )
        let md = notes.toMarkdown()
        #expect(md.contains("## Summary"))
        #expect(!md.contains("## Key Decisions"))
        #expect(!md.contains("## Action Items"))
        #expect(!md.contains("## Open Questions"))
    }

    @Test("Save creates .notes.md file")
    func saveFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let recordingURL = dir.appendingPathComponent("call.m4a")
        FileManager.default.createFile(atPath: recordingURL.path, contents: nil)

        try sampleNotes.save(alongside: recordingURL)

        let notesPath = dir.appendingPathComponent("call.notes.md").path
        #expect(FileManager.default.fileExists(atPath: notesPath))

        let content = try String(contentsOfFile: notesPath, encoding: .utf8)
        #expect(content.contains("# Meeting Notes"))
        #expect(content.contains("Q1 goals"))
    }

    @Test("JSON round-trip")
    func jsonRoundTrip() throws {
        let data = try JSONEncoder().encode(sampleNotes)
        let decoded = try JSONDecoder().decode(MeetingNotes.self, from: data)
        #expect(decoded == sampleNotes)
    }

    @Test("ActionItem equality")
    func actionItemEquality() {
        let a = ActionItem(text: "Do thing", assignee: "Bob")
        let b = ActionItem(text: "Do thing", assignee: "Bob")
        let c = ActionItem(text: "Do thing", assignee: nil)
        #expect(a == b)
        #expect(a != c)
    }
}
