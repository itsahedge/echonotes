import Foundation

/// A single segment of transcribed speech with timing information.
struct TranscriptSegment: Codable, Sendable, Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

/// A complete transcript of a recording, containing timestamped segments.
struct Transcript: Codable, Sendable {
    let segments: [TranscriptSegment]
    let recordingURL: URL
    let createdAt: Date

    /// Plain text — all segments joined with spaces, trimmed.
    func toPlainText() -> String {
        segments.map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Timestamped text with `[MM:SS - MM:SS]` prefixes per segment.
    func toTimestampedText() -> String {
        segments.map { segment in
            let start = Self.formatTimestamp(segment.startTime)
            let end = Self.formatTimestamp(segment.endTime)
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            return "[\(start) - \(end)] \(text)"
        }.joined(separator: "\n")
    }

    /// JSON-encoded representation of the transcript.
    func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Save `.txt` and `.json` files alongside the recording.
    /// Uses atomic writes to prevent orphaned files on partial failure.
    func save() throws {
        let basePath = recordingURL.deletingPathExtension()
        let txtURL = basePath.appendingPathExtension("txt")
        let jsonURL = basePath.appendingPathExtension("json")
        
        // Write JSON first (more likely to fail due to encoding issues)
        do {
            try toJSON().write(to: jsonURL, options: .atomic)
        } catch {
            // Clean up and rethrow
            try? FileManager.default.removeItem(at: jsonURL)
            throw error
        }
        
        // Write plain text
        do {
            try toPlainText().write(to: txtURL, atomically: true, encoding: .utf8)
        } catch {
            // Clean up both files on failure
            try? FileManager.default.removeItem(at: jsonURL)
            try? FileManager.default.removeItem(at: txtURL)
            throw error
        }
    }

    /// Format seconds as `MM:SS` or `H:MM:SS` for display.
    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
