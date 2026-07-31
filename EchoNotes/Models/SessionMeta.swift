import Foundation

/// Sidecar metadata for a session folder (meta.json). Written when recording
/// stops; its presence marks a session as complete. A session folder with
/// meta.json but no transcript.json was never transcribed — the transcription
/// queue picks those up on the next launch.
struct SessionMeta: Codable, Sendable {
    static let filename = "meta.json"
    static let micTrack = "mic"
    static let systemTrack = "system"

    var started: Date
    var ended: Date
    /// Recorded time excluding pauses.
    var durationSeconds: Double
    /// Track name → filename within the session folder ("mic" → "mic.caf").
    var files: [String: String]
    /// Track name → milliseconds the track's first buffer lagged the earliest
    /// track. Applied to transcript timestamps so both tracks share one clock.
    var startOffsetMs: [String: Int]

    enum CodingKeys: String, CodingKey {
        case started
        case ended
        case durationSeconds = "duration_seconds"
        case files
        case startOffsetMs = "start_offset_ms"
    }

    static func url(in dir: URL) -> URL {
        dir.appendingPathComponent(filename)
    }

    static func read(from dir: URL) throws -> SessionMeta {
        let data = try Data(contentsOf: url(in: dir))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionMeta.self, from: data)
    }

    func write(to dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: Self.url(in: dir), options: .atomic)
    }
}
