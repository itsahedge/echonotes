import Testing
import Foundation
@testable import EchoNotes

@Suite("Transcript")
struct TranscriptTests {
    let sampleSegments = [
        TranscriptSegment(startTime: 0, endTime: 15.5, text: " Hello, welcome to the meeting."),
        TranscriptSegment(startTime: 15.5, endTime: 30.0, text: " Let's discuss the roadmap."),
        TranscriptSegment(startTime: 30.0, endTime: 45.2, text: " Sounds good, let's start.")
    ]

    func makeTranscript(segments: [TranscriptSegment]? = nil) -> Transcript {
        Transcript(
            segments: segments ?? sampleSegments,
            recordingURL: URL(fileURLWithPath: "/tmp/test-recording.m4a"),
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )
    }

    @Test("Plain text joins all segments")
    func plainText() {
        let transcript = makeTranscript()
        let text = transcript.toPlainText()
        #expect(text.contains("Hello, welcome to the meeting."))
        #expect(text.contains("Let's discuss the roadmap."))
        #expect(text.contains("Sounds good, let's start."))
        #expect(!text.contains("["))
    }

    @Test("Plain text handles empty segments")
    func plainTextEmpty() {
        let transcript = makeTranscript(segments: [])
        #expect(transcript.toPlainText() == "")
    }

    @Test("Timestamped text includes brackets and times")
    func timestampedText() {
        let transcript = makeTranscript()
        let text = transcript.toTimestampedText()
        #expect(text.contains("[00:00 - 00:15]"))
        #expect(text.contains("[00:15 - 00:30]"))
        #expect(text.contains("[00:30 - 00:45]"))
        #expect(text.contains("Hello, welcome to the meeting."))
    }

    @Test("Timestamp formatting handles hours")
    func timestampFormatHours() {
        let result = Transcript.formatTimestamp(3661)
        #expect(result == "1:01:01")
    }

    @Test("Timestamp formatting for minutes and seconds")
    func timestampFormatMinutes() {
        let result = Transcript.formatTimestamp(125)
        #expect(result == "02:05")
    }

    @Test("Timestamp formatting for zero")
    func timestampFormatZero() {
        #expect(Transcript.formatTimestamp(0) == "00:00")
    }

    @Test("JSON encoding round-trips correctly")
    func jsonRoundTrip() throws {
        let transcript = makeTranscript()
        let json = try transcript.toJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: json)
        #expect(decoded.segments.count == 3)
        #expect(decoded.segments[0].text == " Hello, welcome to the meeting.")
        #expect(decoded.segments[0].startTime == 0)
        #expect(decoded.segments[0].endTime == 15.5)
    }

    @Test("JSON output is valid JSON")
    func jsonIsValid() throws {
        let transcript = makeTranscript()
        let json = try transcript.toJSON()
        let obj = try JSONSerialization.jsonObject(with: json)
        #expect(obj is [String: Any])
    }

    @Test("Save creates txt and json files")
    func saveFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let recordingURL = dir.appendingPathComponent("test.m4a")
        FileManager.default.createFile(atPath: recordingURL.path, contents: nil)

        let transcript = Transcript(
            segments: sampleSegments,
            recordingURL: recordingURL,
            createdAt: Date()
        )
        try transcript.save()

        let txtPath = dir.appendingPathComponent("test.txt").path
        let jsonPath = dir.appendingPathComponent("test.json").path
        #expect(FileManager.default.fileExists(atPath: txtPath))
        #expect(FileManager.default.fileExists(atPath: jsonPath))

        let txtContent = try String(contentsOfFile: txtPath, encoding: .utf8)
        #expect(txtContent.contains("Hello, welcome to the meeting."))
    }

    @Test("TranscriptSegment equality")
    func segmentEquality() {
        let a = TranscriptSegment(startTime: 0, endTime: 10, text: "Hello")
        let b = TranscriptSegment(startTime: 0, endTime: 10, text: "Hello")
        let c = TranscriptSegment(startTime: 0, endTime: 10, text: "World")
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Diarization Tests

    @Test("Plain text includes speaker labels when present")
    func plainTextWithSpeakers() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 10, text: "Hello there", speaker: Speaker.user.rawValue),
            TranscriptSegment(startTime: 10, endTime: 20, text: "Hi, how are you?", speaker: Speaker.remote.rawValue),
        ]
        let transcript = makeTranscript(segments: segments)
        let text = transcript.toPlainText()
        #expect(text.contains("You: Hello there"))
        #expect(text.contains("Them: Hi, how are you?"))
    }

    @Test("Plain text uses newlines with speaker labels")
    func plainTextSpeakerSeparator() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 10, text: "Line one", speaker: "You"),
            TranscriptSegment(startTime: 10, endTime: 20, text: "Line two", speaker: "Them"),
        ]
        let transcript = makeTranscript(segments: segments)
        let text = transcript.toPlainText()
        #expect(text == "You: Line one\nThem: Line two")
    }

    @Test("Plain text without speaker labels still works")
    func plainTextNoSpeakers() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 10, text: "Just text"),
            TranscriptSegment(startTime: 10, endTime: 20, text: "More text"),
        ]
        let transcript = makeTranscript(segments: segments)
        let text = transcript.toPlainText()
        #expect(text == "Just text\nMore text")
    }

    @Test("Timestamped text includes speaker prefix")
    func timestampedTextWithSpeakers() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 15, text: "Hello", speaker: Speaker.user.rawValue),
            TranscriptSegment(startTime: 15, endTime: 30, text: "World", speaker: Speaker.remote.rawValue),
        ]
        let transcript = makeTranscript(segments: segments)
        let text = transcript.toTimestampedText()
        #expect(text.contains("[00:00 - 00:15] You: Hello"))
        #expect(text.contains("[00:15 - 00:30] Them: World"))
    }

    @Test("Timestamped text without speakers has no prefix")
    func timestampedTextNoSpeakers() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 15, text: "Hello"),
        ]
        let transcript = makeTranscript(segments: segments)
        let text = transcript.toTimestampedText()
        #expect(text == "[00:00 - 00:15] Hello")
    }

    @Test("Speaker enum raw values match expected strings")
    func speakerRawValues() {
        #expect(Speaker.user.rawValue == "You")
        #expect(Speaker.remote.rawValue == "Them")
    }

    @Test("Speaker init from raw value works")
    func speakerFromRaw() {
        #expect(Speaker(rawValue: "You") == .user)
        #expect(Speaker(rawValue: "Them") == .remote)
        #expect(Speaker(rawValue: "Unknown") == nil)
    }

    @Test("JSON round-trip preserves speaker labels")
    func jsonRoundTripWithSpeakers() throws {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 10, text: "Hello", speaker: "You"),
            TranscriptSegment(startTime: 10, endTime: 20, text: "Hi", speaker: "Them"),
        ]
        let transcript = makeTranscript(segments: segments)
        let json = try transcript.toJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: json)
        #expect(decoded.segments[0].speaker == "You")
        #expect(decoded.segments[1].speaker == "Them")
    }

    @Test("Empty segments are filtered from plain text")
    func emptySegmentsFiltered() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 5, text: "Hello", speaker: "You"),
            TranscriptSegment(startTime: 5, endTime: 10, text: "   ", speaker: "Them"),
            TranscriptSegment(startTime: 10, endTime: 15, text: "World", speaker: "You"),
        ]
        let transcript = makeTranscript(segments: segments)
        let text = transcript.toPlainText()
        #expect(text == "You: Hello\nYou: World")
    }
}
