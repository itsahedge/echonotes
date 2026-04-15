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
    private var debugLog: DebugLogger { DebugLogger.shared }
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var transcript: Transcript?
    @Published var error: String?
    @Published var isSummarizing = false
    @Published var summary: MeetingSummary?

    // MARK: - AI Provider Settings

    private static let apiKeyDefaultsKey = "openaiAPIKey"
    private static let anthropicApiKeyDefaultsKey = "anthropicAPIKey"
    private static let googleApiKeyDefaultsKey = "googleAPIKey"
    private static let providerDefaultsKey = "aiProvider"
    private static let aiModelDefaultsKey = "aiModel"
    private static let whisperModelDefaultsKey = "whisperModel"
    private static let customEndpointDefaultsKey = "customEndpoint"
    private static let customModelDefaultsKey = "customModel"
    private static let customAPIKeyDefaultsKey = "customAPIKey"
    private static let knowledgeBasePathDefaultsKey = "knowledgeBasePath"
    private static let useKnowledgeBaseDefaultsKey = "useKnowledgeBase"
    private static let anthropicSetupTokenDefaultsKey = "anthropicSetupToken"

    /// API key for the selected AI provider.
    @Published var openaiAPIKey: String = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(openaiAPIKey, forKey: Self.apiKeyDefaultsKey) }
    }

    /// API key for Anthropic.
    @Published var anthropicAPIKey: String = UserDefaults.standard.string(forKey: anthropicApiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(anthropicAPIKey, forKey: Self.anthropicApiKeyDefaultsKey) }
    }

    /// API key for Google Gemini.
    @Published var googleAPIKey: String = UserDefaults.standard.string(forKey: googleApiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(googleAPIKey, forKey: Self.googleApiKeyDefaultsKey) }
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

    /// Custom OpenAI-compatible endpoint URL.
    @Published var customEndpoint: String = UserDefaults.standard.string(forKey: customEndpointDefaultsKey) ?? "http://localhost:8080/v1/chat/completions" {
        didSet { UserDefaults.standard.set(customEndpoint, forKey: Self.customEndpointDefaultsKey) }
    }

    /// Custom model name for the custom endpoint.
    @Published var customModel: String = UserDefaults.standard.string(forKey: customModelDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(customModel, forKey: Self.customModelDefaultsKey) }
    }

    /// Optional API key for the custom endpoint.
    @Published var customAPIKey: String = UserDefaults.standard.string(forKey: customAPIKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(customAPIKey, forKey: Self.customAPIKeyDefaultsKey) }
    }

    /// Path to a knowledge base folder (e.g., Obsidian vault) for contextual summaries.
    @Published var knowledgeBasePath: String = UserDefaults.standard.string(forKey: knowledgeBasePathDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(knowledgeBasePath, forKey: Self.knowledgeBasePathDefaultsKey) }
    }

    /// Whether to include knowledge base context in AI summaries.
    @Published var useKnowledgeBase: Bool = UserDefaults.standard.bool(forKey: useKnowledgeBaseDefaultsKey) {
        didSet { UserDefaults.standard.set(useKnowledgeBase, forKey: Self.useKnowledgeBaseDefaultsKey) }
    }

    /// Setup token from `claude setup-token` for Anthropic subscription auth.
    @Published var anthropicSetupToken: String = UserDefaults.standard.string(forKey: anthropicSetupTokenDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(anthropicSetupToken, forKey: Self.anthropicSetupTokenDefaultsKey) }
    }

    var isAnthropicSubscriptionAuthenticated: Bool {
        !anthropicSetupToken.isEmpty
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
        switch selectedProvider {
        case .openai:
            return oauthManager.isAuthenticated || !openaiAPIKey.isEmpty
        case .anthropic:
            return !anthropicAPIKey.isEmpty || !anthropicSetupToken.isEmpty
        case .google:
            return !googleAPIKey.isEmpty
        case .custom:
            return !customEndpoint.isEmpty
        case .ollama:
            return true
        }
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
                // No API key — use access token against ChatGPT backend
                // (Responses API at chatgpt.com/backend-api/codex/responses)
                return AIService.Configuration(
                    apiKey: tokens.accessToken,
                    model: "gpt-5.2-codex",
                    endpoint: URL(string: "https://chatgpt.com/backend-api/codex/responses")!,
                    provider: selectedProvider,
                    chatgptAccountId: tokens.accountId
                )
            }
        }

        // Anthropic subscription auth via setup token
        if selectedProvider == .anthropic, !anthropicSetupToken.isEmpty {
            return AIService.Configuration(
                apiKey: anthropicSetupToken,
                model: selectedAIModel,
                endpoint: URL(string: selectedProvider.defaultEndpoint)!,
                provider: selectedProvider,
                anthropicBearerAuth: true
            )
        }

        if selectedProvider == .custom {
            return AIService.Configuration(
                apiKey: customAPIKey,
                model: customModel.isEmpty ? "default" : customModel,
                endpoint: URL(string: customEndpoint) ?? URL(string: "http://localhost:8080/v1/chat/completions")!,
                provider: .custom
            )
        }

        // Per-provider API key
        let apiKey: String
        switch selectedProvider {
        case .openai: apiKey = openaiAPIKey
        case .anthropic: apiKey = anthropicAPIKey
        case .google: apiKey = googleAPIKey
        default: apiKey = ""
        }

        return AIService.Configuration(
            apiKey: apiKey,
            model: selectedAIModel,
            endpoint: URL(string: selectedProvider.defaultEndpoint)!,
            provider: selectedProvider
        )
    }

    let modelManager = ModelManager()
    let streamingTranscriber = StreamingTranscriber()
    private var whisperEngine: WhisperEngine?
    private var transcriptionTask: Task<Void, Never>?

    /// The model to use for transcription. Persisted via UserDefaults.
    @Published var selectedModel: WhisperModel = {
        if let raw = UserDefaults.standard.string(forKey: whisperModelDefaultsKey),
           let model = WhisperModel(rawValue: raw) {
            return model
        }
        return .base
    }() {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.whisperModelDefaultsKey) }
    }

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
                await MainActor.run { self.debugLog.info("Starting transcription: \(audioURL.lastPathComponent)", category: "Transcription") }
                let engine = try await modelManager.ensureEngine(for: selectedModel)
                logger.info("Engine ready, transcribing...")
                await MainActor.run { self.debugLog.info("Whisper engine ready (model: \(self.selectedModel.rawValue)), transcribing...", category: "Transcription") }
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
                    self.debugLog.error("Transcription failed: \(error.localizedDescription)", category: "Transcription")
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
            debugLog.info("Summarizing with \(config.provider.rawValue) (\(config.model))", category: "AI")

            // Build knowledge base context if enabled
            var kbContext: String?
            if useKnowledgeBase, !knowledgeBasePath.isEmpty {
                debugLog.info("Loading knowledge base from: \(knowledgeBasePath)", category: "KnowledgeBase")
                let kbService = KnowledgeBaseService()
                kbContext = kbService.buildContext(vaultPath: knowledgeBasePath, transcript: transcript.toPlainText())
                if let ctx = kbContext {
                    debugLog.info("Injecting \(ctx.count) chars of vault context into prompt", category: "KnowledgeBase")
                } else {
                    debugLog.warning("No relevant context found in vault", category: "KnowledgeBase")
                }
            }

            let result = try await service.summarize(transcript: transcript.toPlainText(), config: config, knowledgeBaseContext: kbContext)

            // Save as .md alongside the recording
            let mdURL = transcript.recordingURL.deletingPathExtension().appendingPathExtension("md")
            try result.toMarkdown().write(to: mdURL, atomically: true, encoding: .utf8)

            // Save as .summary.json so RecordingDetailView can load it
            let jsonURL = transcript.recordingURL.deletingPathExtension().appendingPathExtension("summary.json")
            let encoded = try JSONEncoder().encode(result)
            try encoded.write(to: jsonURL, options: .atomic)

            debugLog.info("Summary generated successfully", category: "AI")
            self.summary = result
        } catch {
            debugLog.error("Summary failed: \(error.localizedDescription)", category: "AI")
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

    /// Pause live transcription — flush current chunks and stop accepting new audio
    func pauseLiveTranscription() async {
        await streamingTranscriber.pause()
    }

    /// Resume live transcription — continue processing from where we left off
    func resumeLiveTranscription() async {
        await streamingTranscriber.resume()
    }
}
