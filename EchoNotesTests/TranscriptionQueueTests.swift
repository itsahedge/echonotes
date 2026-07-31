import Testing
import Foundation
@testable import EchoNotes

@Suite("Transcription queue")
struct TranscriptionQueueTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Create a session folder, optionally recorded (meta.json) and
    /// optionally transcribed (transcript.json).
    private func makeSession(_ name: String, recorded: Bool, transcribed: Bool) throws -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("mic.caf").path, contents: Data())
        if recorded {
            let meta = SessionMeta(
                started: Date(), ended: Date(), durationSeconds: 1,
                files: [SessionMeta.micTrack: "mic.caf"],
                startOffsetMs: [SessionMeta.micTrack: 0]
            )
            try meta.write(to: dir)
        }
        if transcribed {
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("transcript.json").path,
                contents: Data("{}".utf8)
            )
        }
        return dir
    }

    @Test("Finds only completed, untranscribed sessions")
    func findsPending() throws {
        _ = try makeSession("recording-2026-07-29_10-00-00", recorded: true, transcribed: false)
        _ = try makeSession("recording-2026-07-29_11-00-00", recorded: true, transcribed: true)
        _ = try makeSession("recording-2026-07-29_12-00-00", recorded: false, transcribed: false)

        let found = TranscriptionManager.findPendingSessions(in: root)
        // Compare by name — /var vs /private/var symlinks make URL equality unreliable.
        #expect(found.map(\.lastPathComponent) == ["recording-2026-07-29_10-00-00"])
    }

    @Test("Pending sessions are ordered oldest-first")
    func oldestFirst() throws {
        _ = try makeSession("recording-2026-07-29_12-00-00", recorded: true, transcribed: false)
        _ = try makeSession("recording-2026-07-28_09-00-00", recorded: true, transcribed: false)

        let found = TranscriptionManager.findPendingSessions(in: root)
        #expect(found.map(\.lastPathComponent) == [
            "recording-2026-07-28_09-00-00",
            "recording-2026-07-29_12-00-00",
        ])
    }

    @Test("Ignores legacy flat recordings")
    func ignoresLegacyFiles() throws {
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("recording-2026-01-01_09-00-00.m4a").path,
            contents: Data()
        )
        #expect(TranscriptionManager.findPendingSessions(in: root).isEmpty)
    }

    @Test("Empty or missing root yields no sessions")
    func emptyRoot() {
        #expect(TranscriptionManager.findPendingSessions(in: root).isEmpty)
        let missing = root.appendingPathComponent("nope")
        #expect(TranscriptionManager.findPendingSessions(in: missing).isEmpty)
    }

    @Test("Session track list uses meta offsets and skips missing files")
    func sessionTracks() throws {
        let dir = try makeSession("recording-2026-07-29_13-00-00", recorded: false, transcribed: false)
        // mic.caf exists (from makeSession); system.caf does not.
        let meta = SessionMeta(
            started: Date(), ended: Date(), durationSeconds: 1,
            files: [SessionMeta.micTrack: "mic.caf", SessionMeta.systemTrack: "system.caf"],
            startOffsetMs: [SessionMeta.micTrack: 1500, SessionMeta.systemTrack: 0]
        )
        try meta.write(to: dir)

        let tracks = TranscriptionManager.sessionTracks(for: dir)
        #expect(tracks.count == 1)
        let mic = try #require(tracks.first)
        #expect(mic.speaker == .user)
        #expect(abs(mic.startOffset - 1.5) < 0.0001)
        #expect(mic.url.lastPathComponent == "mic.caf")
    }

    @Test("Tracks default to zero offset without meta.json")
    func tracksWithoutMeta() throws {
        let dir = try makeSession("recording-2026-07-29_14-00-00", recorded: false, transcribed: false)
        let tracks = TranscriptionManager.sessionTracks(for: dir)
        #expect(tracks.count == 1)
        #expect(tracks.first?.startOffset == 0)
    }
}
