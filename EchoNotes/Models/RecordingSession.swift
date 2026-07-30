import Foundation
import os

/// One meeting recording: a timestamped folder holding two independent audio
/// tracks (mic = you, system = them) plus a meta.json written on stop.
///
/// Tracks are separate on purpose — Whisper does better on clean
/// single-source audio, and two files give two-party diarization for free.
/// Because each track streams straight to its own CAF file there is no
/// cross-stream buffer syncing, and a crash mid-meeting loses nothing
/// already written.
@MainActor
final class RecordingSession {
    let dir: URL
    let startedAt = Date()

    let mic = MicrophoneCapture()
    let system = SystemAudioCapture()

    nonisolated static let micFilename = "mic.caf"
    nonisolated static let systemFilename = "system.caf"

    private let logger = Logger(subsystem: "com.echonotes", category: "RecordingSession")

    private static let folderTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // No dots in the name: a session folder is distinguished from legacy
        // flat recordings by having no path extension (see RecordingArtifacts).
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Create the session folder under `root` (suffixed on collision) without
    /// starting capture yet.
    init(root: URL) throws {
        let base = "recording-" + Self.folderTimestampFormatter.string(from: startedAt)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        dir = candidate
    }

    /// Start both tracks. If the mic fails after the system tap started, the
    /// tap is torn down so we never run half a session silently.
    func start() throws {
        try system.start(writingTo: dir.appendingPathComponent(Self.systemFilename))
        do {
            try mic.start(writingTo: dir.appendingPathComponent(Self.micFilename))
        } catch {
            system.stopCapture()
            throw error
        }
    }

    /// Pause both tracks, keeping their files open for resume.
    func pause() {
        mic.pauseCapture()
        system.pauseCapture()
    }

    /// Resume both tracks. If the mic fails to come back, the system track is
    /// re-paused so the session stays consistently paused.
    func resume() throws {
        try system.resumeCapture()
        do {
            try mic.resumeCapture()
        } catch {
            system.pauseCapture()
            throw error
        }
    }

    /// Stop both tracks and write meta.json. The presence of meta.json marks
    /// the session as complete (and transcribable).
    func stop(recordedDuration: TimeInterval) {
        // Read first-buffer times before stopCapture clears capture state.
        let micStart = mic.firstBufferAt ?? startedAt
        let systemStart = system.firstBufferAt ?? startedAt

        mic.stopCapture()
        system.stopCapture()

        // The tracks don't start on the same buffer; record how far each lags
        // the earliest so transcript timestamps share one clock.
        let earliest = min(micStart, systemStart)
        let meta = SessionMeta(
            started: startedAt,
            ended: Date(),
            durationSeconds: recordedDuration,
            files: [
                SessionMeta.micTrack: Self.micFilename,
                SessionMeta.systemTrack: Self.systemFilename,
            ],
            startOffsetMs: [
                SessionMeta.micTrack: Int(micStart.timeIntervalSince(earliest) * 1000),
                SessionMeta.systemTrack: Int(systemStart.timeIntervalSince(earliest) * 1000),
            ]
        )
        do {
            try meta.write(to: dir)
        } catch {
            logger.error("Failed to write session meta: \(error.localizedDescription)")
        }
    }
}
