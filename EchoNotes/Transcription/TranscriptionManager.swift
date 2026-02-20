import Foundation
import os

/// How transcription should be performed.
enum TranscriptionMode: String, CaseIterable {
    case postRecording = "After Recording"
    case live = "Live"
}

/// Orchestrates the full transcription pipeline: model check → download → transcribe → save.
///
/// **Role as coordinator:**
/// While this might seem like an unnecessary layer, it serves as a clear boundary between
/// recording (RecordingEngine) and transcription (WhisperEngine/StreamingTranscriber).
/// It owns the transcription state (@Published properties), manages the lifecycle of both
/// post-recording and live transcription modes, and provides a single interface for the UI.
/// This separation keeps RecordingEngine focused on audio I/O and allows transcription
/// logic to evolve independently.
@MainActor
final class TranscriptionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.echonotes", category: "TranscriptionManager")
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var transcript: Transcript?
    @Published var error: String?
    @Published var isSummarizing = false
    @Published var summary: MeetingSummary?

    private static let apiKeyDefaultsKey = "openaiAPIKey"

    /// OpenAI API key — stored in UserDefaults, synced via @Published for SwiftUI.
    /// Note: @AppStorage inside ObservableObject causes re-render loops. Use @Published + manual sync.
    @Published var openaiAPIKey: String = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(openaiAPIKey, forKey: Self.apiKeyDefaultsKey) }
    }

    let modelManager = ModelManager()
    let streamingTranscriber = StreamingTranscriber()
    private var whisperEngine: WhisperEngine?
    private var transcriptionTask: Task<Void, Never>?

    /// The model to use for transcription.
    var selectedModel: WhisperModel = .base

    /// Prepare the streaming transcriber with a loaded engine.
    func prepareForLiveTranscription() async throws {
        let engine = try await modelManager.ensureEngine(for: selectedModel)
        whisperEngine = engine
        streamingTranscriber.prepare(engine: engine)
    }

    /// Finalize live transcription — flush remaining audio and build transcript.
    func finalizeLiveTranscription(recordingURL: URL) async {
        await streamingTranscriber.flush()

        let segments = streamingTranscriber.flushedSegments + streamingTranscriber.segments
        guard !segments.isEmpty else { return }

        let result = Transcript(
            segments: segments,
            recordingURL: recordingURL,
            createdAt: Date()
        )
        do {
            try result.save()
        } catch {
            self.error = "Failed to save transcript: \(error.localizedDescription)"
        }
        transcript = result
    }

    /// Cancel a running transcription.
    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
        progress = 0
        error = "Transcription cancelled."
    }

    /// Transcribe an audio file end-to-end.
    func transcribe(audioURL: URL) async {
        guard !isTranscribing else { return }

        isTranscribing = true
        progress = 0
        transcript = nil
        error = nil

        let task = Task {
            do {
                logger.info("Starting transcription for \(audioURL.lastPathComponent)")
                let engine = try await modelManager.ensureEngine(for: selectedModel)
                logger.info("Engine ready, transcribing...")
                whisperEngine = engine

                try Task.checkCancellation()

                let segments = try await engine.transcribeDiarized(audioURL: audioURL) { [weak self] progress in
                    Task { @MainActor in
                        self?.progress = progress
                    }
                }

                try Task.checkCancellation()

                let result = Transcript(
                    segments: segments,
                    recordingURL: audioURL,
                    createdAt: Date()
                )
                try result.save()

                await MainActor.run {
                    self.transcript = result
                    self.progress = 1.0
                }
            } catch is CancellationError {
                // Already handled by cancel()
            } catch {
                logger.error("Transcription failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }

            await MainActor.run {
                self.isTranscribing = false
            }
        }

        transcriptionTask = task
        await task.value
    }

    /// Summarize the current transcript using OpenAI.
    func summarize() async {
        guard let transcript else { return }
        guard !openaiAPIKey.isEmpty else {
            error = AIError.noAPIKey.localizedDescription
            return
        }

        isSummarizing = true
        error = nil
        summary = nil

        do {
            let config = AIService.Configuration(apiKey: openaiAPIKey)
            let service = AIService()
            let result = try await service.summarize(transcript: transcript.toPlainText(), config: config)

            // Save as .md alongside the recording
            let mdURL = transcript.recordingURL.deletingPathExtension().appendingPathExtension("md")
            try result.toMarkdown().write(to: mdURL, atomically: true, encoding: .utf8)

            self.summary = result
        } catch {
            self.error = error.localizedDescription
        }

        isSummarizing = false
    }

    /// Reset state for a new transcription.
    func reset() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcript = nil
        error = nil
        progress = 0
        summary = nil
    }
}
