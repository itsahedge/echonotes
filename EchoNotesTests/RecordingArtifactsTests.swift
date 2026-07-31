import Testing
import Foundation
@testable import EchoNotes

@Suite("RecordingArtifacts")
struct RecordingArtifactsTests {
    @Test("Session folders resolve artifacts inside the folder")
    func sessionLayout() {
        let dir = URL(fileURLWithPath: "/tmp/EchoNotes/recording-2026-07-29_14-05-00", isDirectory: true)
        let artifacts = RecordingArtifacts(recordingURL: dir)

        #expect(artifacts.transcriptJSON.path == dir.appendingPathComponent("transcript.json").path)
        #expect(artifacts.transcriptText.path == dir.appendingPathComponent("transcript.txt").path)
        #expect(artifacts.summaryJSON.path == dir.appendingPathComponent("summary.json").path)
        #expect(artifacts.summaryMarkdown.path == dir.appendingPathComponent("summary.md").path)
    }

    @Test("Legacy recordings resolve artifacts as siblings")
    func legacyLayout() {
        let file = URL(fileURLWithPath: "/tmp/EchoNotes/recording-2026-01-15_10-00-00.m4a")
        let artifacts = RecordingArtifacts(recordingURL: file)

        #expect(artifacts.transcriptJSON.lastPathComponent == "recording-2026-01-15_10-00-00.json")
        #expect(artifacts.transcriptText.lastPathComponent == "recording-2026-01-15_10-00-00.txt")
        #expect(artifacts.summaryJSON.lastPathComponent == "recording-2026-01-15_10-00-00.summary.json")
        #expect(artifacts.summaryMarkdown.lastPathComponent == "recording-2026-01-15_10-00-00.md")
    }

    @Test("Session detection by path extension")
    func sessionDetection() {
        #expect(RecordingArtifacts.isSessionDirectory(URL(fileURLWithPath: "/a/recording-2026-07-29_14-05-00")))
        #expect(!RecordingArtifacts.isSessionDirectory(URL(fileURLWithPath: "/a/recording-2026-07-29.m4a")))
    }

    @Test("Detection survives round-tripping through persisted JSON")
    func sessionDetectionAfterDecode() throws {
        // Directory-ness is lost when a URL is decoded from transcript.json;
        // the extension rule must still classify correctly.
        let original = URL(fileURLWithPath: "/tmp/EchoNotes/recording-2026-07-29_14-05-00", isDirectory: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(URL.self, from: data)
        #expect(RecordingArtifacts.isSessionDirectory(decoded))
    }
}
