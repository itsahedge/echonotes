import Foundation
@preconcurrency import AVFoundation
import os

/// A single recording entry in the library.
struct RecordingEntry: Identifiable, Sendable {
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

    /// Load a Transcript from the associated .json file, if it exists.
    func loadTranscript() -> Transcript? {
        let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let transcript = try? JSONDecoder().decode(Transcript.self, from: data) else {
            return nil
        }
        return transcript
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
        let query = searchQuery.lowercased()
        return entries.filter { entry in
            entry.filename.lowercased().contains(query) ||
            (entry.fullTranscriptText?.lowercased().contains(query) ?? false)
        }
    }

    private var saveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("EchoNotes", isDirectory: true)
    }

    /// Scan the recordings directory for entries. File I/O runs on a background thread.
    func scan() {
        let directory = saveDirectory
        Task.detached(priority: .userInitiated) { [weak self] in
            let results = Self.scanDirectory(directory)
            await MainActor.run {
                self?.entries = results
                self?.logger.info("Library scan: found \(results.count) recordings")
            }
        }
    }

    /// Pure scanning logic — runs off the main thread.
    nonisolated private static func scanDirectory(_ directory: URL) -> [RecordingEntry] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }

        let m4aFiles = files.filter { $0.pathExtension.lowercased() == "m4a" }

        var results: [RecordingEntry] = []
        for fileURL in m4aFiles {
            let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let duration = getAudioDuration(url: fileURL)
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
        ]
        for url in urls where fm.fileExists(atPath: url.path) {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
        entries.removeAll { $0.id == entry.id }
    }

    nonisolated private static func getAudioDuration(url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
}
