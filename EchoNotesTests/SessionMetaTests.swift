import Testing
import Foundation
@testable import EchoNotes

@Suite("SessionMeta")
struct SessionMetaTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    private func makeMeta(started: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> SessionMeta {
        SessionMeta(
            started: started,
            ended: started.addingTimeInterval(125),
            durationSeconds: 120,
            files: [SessionMeta.micTrack: "mic.caf", SessionMeta.systemTrack: "system.caf"],
            startOffsetMs: [SessionMeta.micTrack: 40, SessionMeta.systemTrack: 0]
        )
    }

    @Test("Round-trips through meta.json")
    func roundTrip() throws {
        let meta = makeMeta()
        try meta.write(to: tempDir)

        let read = try SessionMeta.read(from: tempDir)
        #expect(abs(read.started.timeIntervalSince(meta.started)) < 1)
        #expect(read.durationSeconds == 120)
        #expect(read.files[SessionMeta.micTrack] == "mic.caf")
        #expect(read.startOffsetMs[SessionMeta.micTrack] == 40)
        #expect(read.startOffsetMs[SessionMeta.systemTrack] == 0)
    }

    @Test("Uses snake_case keys on disk")
    func snakeCaseKeys() throws {
        try makeMeta().write(to: tempDir)
        let text = try String(contentsOf: SessionMeta.url(in: tempDir), encoding: .utf8)
        #expect(text.contains("\"duration_seconds\""))
        #expect(text.contains("\"start_offset_ms\""))
    }

    @Test("Reading a folder without meta.json throws")
    func missingMeta() {
        #expect(throws: (any Error).self) {
            try SessionMeta.read(from: tempDir)
        }
    }
}
