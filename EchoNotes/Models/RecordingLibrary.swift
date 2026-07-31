import Foundation
@preconcurrency import AVFoundation
import os

/// A single recording entry in the library.
struct RecordingEntry: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let date: Date
    let duration: TimeInterval
    /// First ~150 chars of transcript for display in list rows.
    let transcriptPreview: String?
    /// Full transcript text for search. Not displayed directly.
    let fullTranscriptText: String?
    let hasTranscript: Bool

    var filename: String { url.lastPathComponent }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RecordingEntry, rhs: RecordingEntry) -> Bool {
        lhs.id == rhs.id &&
        lhs.hasTranscript == rhs.hasTranscript &&
        lhs.transcriptPreview == rhs.transcriptPreview
    }

    /// Load a Transcript from the associated .json file, falling back to .txt if needed.
    func loadTranscript() -> Transcript? {
        let artifacts = RecordingArtifacts(recordingURL: url)

        // Try structured JSON first
        let jsonURL = artifacts.transcriptJSON
        if FileManager.default.fileExists(atPath: jsonURL.path),
           let data = try? Data(contentsOf: jsonURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let transcript = try? decoder.decode(Transcript.self, from: data) {
                return transcript
            }
        }

        // Fall back to plain .txt file
        let txtURL = artifacts.transcriptText
        if FileManager.default.fileExists(atPath: txtURL.path),
           let text = try? String(contentsOf: txtURL, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Create a simple transcript with the full text as one segment
            let segment = TranscriptSegment(startTime: 0, endTime: duration, text: text)
            return Transcript(
                segments: [segment],
                recordingURL: url,
                createdAt: date
            )
        }

        return nil
    }
}

/// Scans ~/Documents/EchoNotes/ for past recordings and their transcripts.
@MainActor
@Observable
final class RecordingLibrary {
    @ObservationIgnored private let logger = Logger(subsystem: "com.echonotes", category: "RecordingLibrary")
    var entries: [RecordingEntry] = []
    var searchQuery: String = ""
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = 0

    var filteredEntries: [RecordingEntry] {
        guard !searchQuery.isEmpty else { return entries }
        return entries.filter { entry in
            entry.filename.localizedStandardContains(searchQuery) ||
            (entry.fullTranscriptText?.localizedStandardContains(searchQuery) ?? false)
        }
    }

    private var saveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("EchoNotes", isDirectory: true)
    }

    /// Scan the recordings directory for entries. File I/O runs on a background thread.
    func scan() {
        requestRefresh()
    }

    func requestRefresh() {
        let directory = saveDirectory
        scanGeneration += 1
        let generation = scanGeneration

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }

            let results = await withTaskGroup(of: [RecordingEntry].self) { group in
                group.addTask(priority: .userInitiated) {
                    await Self.scanDirectory(directory)
                }
                return await group.next() ?? []
            }

            guard !Task.isCancelled else { return }
            guard let self, generation == self.scanGeneration else { return }

            self.entries = results
            self.logger.info("Library scan: found \(results.count) recordings")
        }
    }

    /// Pure scanning logic — runs off the main thread. Picks up both session
    /// folders (mic.caf + system.caf + meta.json) and legacy flat .m4a files.
    nonisolated private static func scanDirectory(_ directory: URL) async -> [RecordingEntry] {
        guard !Task.isCancelled else { return [] }

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]
        ) else {
            return []
        }

        var results: [RecordingEntry] = []
        for url in items {
            guard !Task.isCancelled else { return results }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                guard isSessionFolder(url), let entry = await sessionEntry(for: url) else { continue }
                results.append(entry)
            } else if url.pathExtension.lowercased() == "m4a" {
                results.append(await legacyEntry(for: url))
            }
        }

        return results.sorted { $0.date > $1.date }
    }

    nonisolated private static func isSessionFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent(RecordingSession.micFilename).path)
            || fm.fileExists(atPath: url.appendingPathComponent(RecordingSession.systemFilename).path)
            || fm.fileExists(atPath: SessionMeta.url(in: url).path)
    }

    nonisolated private static func sessionEntry(for dir: URL) async -> RecordingEntry? {
        let meta = try? SessionMeta.read(from: dir)
        let date = meta?.started
            ?? (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            ?? Date.distantPast

        var duration = meta?.durationSeconds ?? 0
        if duration <= 0 {
            // Meta missing (crash mid-recording) — measure a track instead.
            duration = await getAudioDuration(url: dir.appendingPathComponent(RecordingSession.systemFilename))
            if duration <= 0 {
                duration = await getAudioDuration(url: dir.appendingPathComponent(RecordingSession.micFilename))
            }
        }

        let (preview, fullText, hasTranscript) = transcriptInfo(for: dir)
        return RecordingEntry(
            id: dir,
            url: dir,
            date: date,
            duration: duration,
            transcriptPreview: preview,
            fullTranscriptText: fullText,
            hasTranscript: hasTranscript
        )
    }

    nonisolated private static func legacyEntry(for fileURL: URL) async -> RecordingEntry {
        let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
        let duration = await getAudioDuration(url: fileURL)
        let (preview, fullText, hasTranscript) = transcriptInfo(for: fileURL)

        return RecordingEntry(
            id: fileURL,
            url: fileURL,
            date: date,
            duration: duration,
            transcriptPreview: preview,
            fullTranscriptText: fullText,
            hasTranscript: hasTranscript
        )
    }

    nonisolated private static func transcriptInfo(
        for recordingURL: URL
    ) -> (preview: String?, fullText: String?, hasTranscript: Bool) {
        let fm = FileManager.default
        let artifacts = RecordingArtifacts(recordingURL: recordingURL)
        let hasTranscript = fm.fileExists(atPath: artifacts.transcriptText.path)
            || fm.fileExists(atPath: artifacts.transcriptJSON.path)

        var fullText: String?
        var preview: String?
        if let text = try? String(contentsOf: artifacts.transcriptText, encoding: .utf8) {
            fullText = text
            preview = String(text.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (preview, fullText, hasTranscript)
    }

    func delete(_ entry: RecordingEntry) {
        let fm = FileManager.default
        // Move to trash instead of permanent delete
        if RecordingArtifacts.isSessionDirectory(entry.url) {
            // Session folder — everything lives inside it.
            try? fm.trashItem(at: entry.url, resultingItemURL: nil)
        } else {
            let urls = [
                entry.url,
                entry.url.deletingPathExtension().appendingPathExtension("txt"),
                entry.url.deletingPathExtension().appendingPathExtension("json"),
                entry.url.deletingPathExtension().appendingPathExtension("md"),
                entry.url.deletingPathExtension().appendingPathExtension("summary.json"),
            ]
            for url in urls where fm.fileExists(atPath: url.path) {
                try? fm.trashItem(at: url, resultingItemURL: nil)
            }
        }
        entries.removeAll { $0.id == entry.id }
    }

    nonisolated private static func getAudioDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        return CMTimeGetSeconds(duration)
    }
}
