import Foundation

/// How transcription should be performed.
enum TranscriptionMode: String, CaseIterable {
    case postRecording = "After Recording"
    case live = "Live"
}

/// Orchestrates the full transcription pipeline: model check → download → transcribe → save.
@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var transcript: Transcript?
    @Published var error: String?

    let modelManager = ModelManager()
    let streamingTranscriber = StreamingTranscriber()
    private var whisperEngine: WhisperEngine?
    private var transcriptionTask: Task<Void, Never>?

    /// The model to use for transcription.
    var selectedModel: WhisperModel = .base

    /// Whether the model is currently being downloaded.
    var isDownloadingModel: Bool { modelManager.isDownloading }

    /// Model download progress (0.0–1.0).
    var downloadProgress: Double { modelManager.downloadProgress }

    /// Prepare the streaming transcriber with a loaded engine.
    func prepareForLiveTranscription() async throws {
        let engine = try await modelManager.ensureEngine(for: selectedModel)
        whisperEngine = engine
        streamingTranscriber.prepare(engine: engine)
    }

    /// Finalize live transcription — flush remaining audio and build transcript.
    func finalizeLiveTranscription(recordingURL: URL) async {
        await streamingTranscriber.flush()

        let segments = streamingTranscriber.segments
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
                let engine = try await modelManager.ensureEngine(for: selectedModel)
                whisperEngine = engine

                try Task.checkCancellation()

                let segments = try await engine.transcribe(audioURL: audioURL) { [weak self] progress in
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

    /// Reset state for a new transcription.
    func reset() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcript = nil
        error = nil
        progress = 0
    }
}
