import Foundation

/// How transcription should be performed.
enum TranscriptionMode: String, CaseIterable {
    case postRecording = "After Recording"
    case live = "Live"
}

/// Orchestrates the full transcription pipeline: model check → download → convert → transcribe → save.
@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var transcript: Transcript?
    @Published var error: String?

    let modelManager = ModelManager()
    let streamingTranscriber = StreamingTranscriber()
    private var whisperEngine: WhisperEngine?
    private var loadedModel: WhisperModel?
    private var transcriptionTask: Task<Void, Never>?

    /// The model to use for transcription.
    var selectedModel: WhisperModel = .baseEn

    /// Prepare the streaming transcriber with a loaded engine (call before recording starts).
    func prepareForLiveTranscription() async throws {
        let modelPath = try await modelManager.ensureModel(selectedModel)
        if whisperEngine == nil || loadedModel != selectedModel {
            whisperEngine = try WhisperEngine(modelPath: modelPath)
            loadedModel = selectedModel
        }
        streamingTranscriber.prepare(engine: whisperEngine!)
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

    /// Whether the model is currently being downloaded.
    var isDownloadingModel: Bool { modelManager.isDownloading }

    /// Model download progress (0.0–1.0).
    var downloadProgress: Double { modelManager.downloadProgress }

    /// Cancel a running transcription.
    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
        progress = 0
        error = "Transcription cancelled."
    }

    /// Transcribe an audio file end-to-end.
    /// Ensures the model is available (downloading if needed), loads it, runs inference, and saves results.
    func transcribe(audioURL: URL) async {
        guard !isTranscribing else { return }

        isTranscribing = true
        progress = 0
        transcript = nil
        error = nil

        let task = Task {
            do {
                // Step 1: Ensure model is downloaded
                let modelPath = try await modelManager.ensureModel(selectedModel)

                try Task.checkCancellation()

                // Step 2: Load engine if needed (or reload if model changed)
                if whisperEngine == nil || loadedModel != selectedModel {
                    whisperEngine = try WhisperEngine(modelPath: modelPath)
                    loadedModel = selectedModel
                }

                try Task.checkCancellation()

                // Step 3: Run transcription
                let segments = try await whisperEngine!.transcribe(audioURL: audioURL) { [weak self] progress in
                    Task { @MainActor in
                        self?.progress = progress
                    }
                }

                try Task.checkCancellation()

                // Step 4: Build transcript
                let result = Transcript(
                    segments: segments,
                    recordingURL: audioURL,
                    createdAt: Date()
                )

                // Step 5: Save alongside recording
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
