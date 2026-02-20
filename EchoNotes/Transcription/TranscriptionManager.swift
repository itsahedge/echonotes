import Combine
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

    // MARK: - AI Provider Settings

    private static let apiKeyDefaultsKey = "openaiAPIKey"
    private static let providerDefaultsKey = "aiProvider"
    private static let aiModelDefaultsKey = "aiModel"

    /// API key for the selected AI provider.
    @Published var openaiAPIKey: String = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(openaiAPIKey, forKey: Self.apiKeyDefaultsKey) }
    }

    /// Selected AI provider for summarization.
    @Published var selectedProvider: AIProvider = {
        if let raw = UserDefaults.standard.string(forKey: providerDefaultsKey),
           let provider = AIProvider(rawValue: raw) {
            return provider
        }
        return .openai
    }() {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.providerDefaultsKey) }
    }

    /// Selected model for AI summarization.
    @Published var selectedAIModel: String = UserDefaults.standard.string(forKey: aiModelDefaultsKey) ?? AIProvider.openai.defaultModel {
        didSet { UserDefaults.standard.set(selectedAIModel, forKey: Self.aiModelDefaultsKey) }
    }

    /// OAuth manager for ChatGPT login
    let oauthManager = OAuthManager()
    private var oauthCancellable: AnyCancellable?

    init() {
        // Forward OAuthManager changes to trigger SwiftUI updates
        oauthCancellable = oauthManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Whether the current provider is configured and ready to use.
    var isAIConfigured: Bool {
        // If using OpenAI with OAuth and we got an API key from token exchange
        if selectedProvider == .openai, let tokens = oauthManager.storedTokens, tokens.apiKey != nil {
            return true
        }
        if selectedProvider.requiresAPIKey {
            return !openaiAPIKey.isEmpty
        }
        return true // Ollama doesn't need a key
    }

    /// Build an AIService.Configuration from current settings.
    func aiConfiguration() -> AIService.Configuration {
        // Prefer OAuth for OpenAI if available
        if selectedProvider == .openai, let tokens = oauthManager.storedTokens {
            if let apiKey = tokens.apiKey {
                // Has platform API key — use standard OpenAI endpoint
                return AIService.Configuration(
                    apiKey: apiKey,
                    model: selectedAIModel,
                    endpoint: URL(string: selectedProvider.defaultEndpoint)!,
                    provider: selectedProvider
                )
            } else {
                // No platform API key — token exchange failed.
                // The access token can't be used against api.openai.com directly.
                // User needs to set up billing on platform.openai.com for the
                // token exchange to produce an API key.
                // Fall back to manual API key if available.
                if !openaiAPIKey.isEmpty {
                    return AIService.Configuration(
                        apiKey: openaiAPIKey,
                        model: selectedAIModel,
                        endpoint: URL(string: selectedProvider.defaultEndpoint)!,
                        provider: selectedProvider
                    )
                }
                // Return config with empty key — isAIConfigured will catch this
                return AIService.Configuration(
                    apiKey: "",
                    model: selectedAIModel,
                    endpoint: URL(string: selectedProvider.defaultEndpoint)!,
                    provider: selectedProvider
                )
            }
        }

        return AIService.Configuration(
            apiKey: openaiAPIKey,
            model: selectedAIModel,
            endpoint: URL(string: selectedProvider.defaultEndpoint)!,
            provider: selectedProvider
        )
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

    /// Summarize the current transcript using the configured AI provider.
    func summarize() async {
        guard let transcript else { return }
        guard isAIConfigured else {
            error = AIError.noAPIKey.localizedDescription
            return
        }

        isSummarizing = true
        error = nil
        summary = nil

        do {
            let config = aiConfiguration()
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
