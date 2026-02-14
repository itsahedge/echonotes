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
}
