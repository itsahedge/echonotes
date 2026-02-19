import Testing
import Foundation
@testable import EchoNotes

@Suite("RecordingLibrary")
struct RecordingLibraryTests {

    // MARK: - RecordingEntry

    @Test("RecordingEntry filename extracts last path component")
    func entryFilename() {
        let entry = makeEntry(name: "meeting-2026-01-15.m4a")
        #expect(entry.filename == "meeting-2026-01-15.m4a")
    }

    @Test("RecordingEntry without transcript has nil preview")
    func entryNoTranscript() {
        let entry = makeEntry(name: "test.m4a", transcriptPreview: nil, fullText: nil, hasTranscript: false)
        #expect(entry.transcriptPreview == nil)
        #expect(entry.fullTranscriptText == nil)
        #expect(!entry.hasTranscript)
    }

    // MARK: - Filtering

    @Test("filteredEntries returns all when query is empty")
    func filterEmpty() async {
        let library = await makeLibrary(entries: [
            makeEntry(name: "a.m4a"),
            makeEntry(name: "b.m4a"),
        ])
        let filtered = await library.filteredEntries
        #expect(filtered.count == 2)
    }

    @Test("filteredEntries matches filename")
    func filterByFilename() async {
        let library = await makeLibrary(entries: [
            makeEntry(name: "standup-monday.m4a"),
            makeEntry(name: "interview-bob.m4a"),
        ])
        await MainActor.run { library.searchQuery = "standup" }
        let filtered = await library.filteredEntries
        #expect(filtered.count == 1)
        #expect(filtered[0].filename == "standup-monday.m4a")
    }

    @Test("filteredEntries searches full transcript text, not just preview")
    func filterByFullText() async {
        let longText = String(repeating: "padding ", count: 30) + "unique-keyword-here"
        let library = await makeLibrary(entries: [
            makeEntry(name: "test.m4a", transcriptPreview: "padding padding...", fullText: longText, hasTranscript: true),
        ])
        await MainActor.run { library.searchQuery = "unique-keyword-here" }
        let filtered = await library.filteredEntries
        #expect(filtered.count == 1)
    }

    @Test("filteredEntries search is case-insensitive")
    func filterCaseInsensitive() async {
        let library = await makeLibrary(entries: [
            makeEntry(name: "Meeting.m4a", fullText: "Discussion about ROADMAP"),
        ])
        await MainActor.run { library.searchQuery = "roadmap" }
        let filtered = await library.filteredEntries
        #expect(filtered.count == 1)
    }

    @Test("filteredEntries returns empty for no matches")
    func filterNoMatch() async {
        let library = await makeLibrary(entries: [
            makeEntry(name: "test.m4a", fullText: "Hello world"),
        ])
        await MainActor.run { library.searchQuery = "nonexistent" }
        let filtered = await library.filteredEntries
        #expect(filtered.count == 0)
    }

    // MARK: - Delete

    @Test("delete removes entry from array")
    func deleteRemovesEntry() async {
        let entry1 = makeEntry(name: "a.m4a")
        let entry2 = makeEntry(name: "b.m4a")
        let library = await makeLibrary(entries: [entry1, entry2])

        await library.delete(entry1)
        let remaining = await library.entries
        #expect(remaining.count == 1)
        #expect(remaining[0].filename == "b.m4a")
    }

    // MARK: - Helpers

    private func makeEntry(
        name: String,
        transcriptPreview: String? = nil,
        fullText: String? = nil,
        hasTranscript: Bool = false
    ) -> RecordingEntry {
        let url = URL(fileURLWithPath: "/tmp/EchoNotes/\(name)")
        return RecordingEntry(
            id: url,
            url: url,
            date: Date(),
            duration: 60,
            transcriptPreview: transcriptPreview,
            fullTranscriptText: fullText,
            hasTranscript: hasTranscript
        )
    }

    @MainActor
    private func makeLibrary(entries: [RecordingEntry]) -> RecordingLibrary {
        let library = RecordingLibrary()
        library.entries = entries
        return library
    }
}
