import Foundation

/// Orchestrates the full transcription pipeline: model check → download → convert → transcribe → save.
@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var transcript: Transcript?
    @Published var error: String?

    let modelManager = ModelManager()
    private var whisperEngine: WhisperEngine?
    private var loadedModel: WhisperModel?

    /// The model to use for transcription.
    var selectedModel: WhisperModel = .baseEn

    /// Whether the model is currently being downloaded.
    var isDownloadingModel: Bool { modelManager.isDownloading }

    /// Model download progress (0.0–1.0).
    var downloadProgress: Double { modelManager.downloadProgress }

    /// Transcribe an audio file end-to-end.
    /// Ensures the model is available (downloading if needed), loads it, runs inference, and saves results.
    func transcribe(audioURL: URL) async {
        guard !isTranscribing else { return }

        isTranscribing = true
        progress = 0
        transcript = nil
        error = nil

        do {
            // Step 1: Ensure model is downloaded
            let modelPath = try await modelManager.ensureModel(selectedModel)

            // Step 2: Load engine if needed (or reload if model changed)
            if whisperEngine == nil || loadedModel != selectedModel {
                whisperEngine = try WhisperEngine(modelPath: modelPath)
                loadedModel = selectedModel
            }

            // Step 3: Run transcription
            let segments = try await whisperEngine!.transcribe(audioURL: audioURL) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress
                }
            }

            // Step 4: Build transcript
            let result = Transcript(
                segments: segments,
                recordingURL: audioURL,
                createdAt: Date()
            )

            // Step 5: Save alongside recording
            try result.save()

            transcript = result
            progress = 1.0
        } catch {
            self.error = error.localizedDescription
        }

        isTranscribing = false
    }

    /// Reset state for a new transcription.
    func reset() {
        transcript = nil
        error = nil
        progress = 0
    }
}
