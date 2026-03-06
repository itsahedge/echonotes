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
        // Try structured JSON first
        let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: jsonURL.path),
           let data = try? Data(contentsOf: jsonURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let transcript = try? decoder.decode(Transcript.self, from: data) {
                return transcript
            }
        }

        // Fall back to plain .txt file
        let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
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
final class RecordingLibrary: ObservableObject {
    private let logger = Logger(subsystem: "com.echonotes", category: "RecordingLibrary")
    @Published var entries: [RecordingEntry] = []
    @Published var searchQuery: String = ""

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
        let directory = saveDirectory
        Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) {
                await Self.scanDirectory(directory)
            }.value
            self?.entries = results
            self?.logger.info("Library scan: found \(results.count) recordings")
        }
    }

    /// Pure scanning logic — runs off the main thread.
    nonisolated private static func scanDirectory(_ directory: URL) async -> [RecordingEntry] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }

        let m4aFiles = files.filter { $0.pathExtension.lowercased() == "m4a" }

        var results: [RecordingEntry] = []
        for fileURL in m4aFiles {
            let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let duration = await getAudioDuration(url: fileURL)
            let txtURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
            let jsonURL = fileURL.deletingPathExtension().appendingPathExtension("json")
            let hasTranscript = fm.fileExists(atPath: txtURL.path) || fm.fileExists(atPath: jsonURL.path)

            var fullText: String?
            var preview: String?
            if let text = try? String(contentsOf: txtURL, encoding: .utf8) {
                fullText = text
                preview = String(text.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            results.append(RecordingEntry(
                id: fileURL,
                url: fileURL,
                date: date,
                duration: duration,
                transcriptPreview: preview,
                fullTranscriptText: fullText,
                hasTranscript: hasTranscript
            ))
        }

        return results.sorted { $0.date > $1.date }
    }

    func delete(_ entry: RecordingEntry) {
        let fm = FileManager.default
        // Move to trash instead of permanent delete
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
        entries.removeAll { $0.id == entry.id }
    }

    nonisolated private static func getAudioDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        return CMTimeGetSeconds(duration)
    }
}
