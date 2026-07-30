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
/// It owns the transcription state, manages the lifecycle of both post-recording and live
/// transcription modes, and provides a single interface for the UI. This separation keeps
/// RecordingEngine focused on audio I/O and allows transcription logic to evolve independently.
@MainActor
@Observable
final class TranscriptionManager {
    @ObservationIgnored private let logger = Logger(subsystem: "com.echonotes", category: "TranscriptionManager")
    @ObservationIgnored private var debugLog: DebugLogger { DebugLogger.shared }

    var isTranscribing = false
    var progress: Double = 0
    var transcript: Transcript?
    var error: String?
    var isSummarizing = false
    var summary: MeetingSummary?

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

    /// API key for the selected AI provider.
    var openaiAPIKey: String = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(openaiAPIKey, forKey: Self.apiKeyDefaultsKey) }
    }

    /// API key for Anthropic.
    var anthropicAPIKey: String = UserDefaults.standard.string(forKey: anthropicApiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(anthropicAPIKey, forKey: Self.anthropicApiKeyDefaultsKey) }
    }

    /// API key for Google Gemini.
    var googleAPIKey: String = UserDefaults.standard.string(forKey: googleApiKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(googleAPIKey, forKey: Self.googleApiKeyDefaultsKey) }
    }

    /// Selected AI provider for summarization.
    var selectedProvider: AIProvider = {
        if let raw = UserDefaults.standard.string(forKey: providerDefaultsKey),
           let provider = AIProvider(rawValue: raw) {
            return provider
        }
        return .openai
    }() {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.providerDefaultsKey) }
    }

    /// Selected model for AI summarization.
    var selectedAIModel: String = UserDefaults.standard.string(forKey: aiModelDefaultsKey) ?? AIProvider.openai.defaultModel {
        didSet { UserDefaults.standard.set(selectedAIModel, forKey: Self.aiModelDefaultsKey) }
    }

    /// Custom OpenAI-compatible endpoint URL.
    var customEndpoint: String = UserDefaults.standard.string(forKey: customEndpointDefaultsKey) ?? "http://localhost:8080/v1/chat/completions" {
        didSet { UserDefaults.standard.set(customEndpoint, forKey: Self.customEndpointDefaultsKey) }
    }

    /// Custom model name for the custom endpoint.
    var customModel: String = UserDefaults.standard.string(forKey: customModelDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(customModel, forKey: Self.customModelDefaultsKey) }
    }

    /// Optional API key for the custom endpoint.
    var customAPIKey: String = UserDefaults.standard.string(forKey: customAPIKeyDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(customAPIKey, forKey: Self.customAPIKeyDefaultsKey) }
    }

    /// Path to a knowledge base folder (e.g., Obsidian vault) for contextual summaries.
    var knowledgeBasePath: String = UserDefaults.standard.string(forKey: knowledgeBasePathDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(knowledgeBasePath, forKey: Self.knowledgeBasePathDefaultsKey) }
    }

    /// Whether to include knowledge base context in AI summaries.
    var useKnowledgeBase: Bool = UserDefaults.standard.bool(forKey: useKnowledgeBaseDefaultsKey) {
        didSet { UserDefaults.standard.set(useKnowledgeBase, forKey: Self.useKnowledgeBaseDefaultsKey) }
    }

    /// OAuth manager for ChatGPT login. Views that read `oauthManager.x` register observation
    /// through the Observation framework directly, so no Combine bridge is needed.
    let oauthManager = OAuthManager()

    /// Whether the current provider is configured and ready to use.
    var isAIConfigured: Bool {
        // OAuth: either API key or access token via ChatGPT backend
        if selectedProvider == .openai, oauthManager.isAuthenticated {
            return true
        }
        if selectedProvider == .custom {
            return !customEndpoint.isEmpty
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

        if selectedProvider == .custom {
            return AIService.Configuration(
                apiKey: customAPIKey,
                model: customModel.isEmpty ? "default" : customModel,
                endpoint: URL(string: customEndpoint) ?? URL(string: "http://localhost:8080/v1/chat/completions")!,
                provider: .custom
            )
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
    @ObservationIgnored private var whisperEngine: WhisperEngine?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?

    /// The model to use for transcription. Persisted via UserDefaults.
    var selectedModel: WhisperModel = {
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

    // MARK: - Transcription queue

    @ObservationIgnored private var pendingTranscriptions: [URL] = []
    @ObservationIgnored private var isDrainingQueue = false

    /// Queue a recording for transcription. Jobs run one at a time, in order;
    /// a failure logs and never blocks later jobs.
    func enqueue(_ url: URL) {
        guard !pendingTranscriptions.contains(url) else { return }
        pendingTranscriptions.append(url)
        drainQueueIfIdle()
    }

    /// The filesystem is the queue: a session folder with meta.json but no
    /// transcript.json finished recording but was never transcribed (app quit
    /// or crashed mid-job). Re-queue those on launch.
    func resumePendingSessions(in root: URL) {
        let pending = Self.findPendingSessions(in: root)
        guard !pending.isEmpty else { return }
        logger.info("Resuming \(pending.count) untranscribed session(s)")
        debugLog.info("Resuming \(pending.count) untranscribed session(s)", category: "Transcription")
        for dir in pending {
            enqueue(dir)
        }
    }

    /// Session folders under `root` that completed recording (meta.json
    /// exists) but have no transcript.json. Sorted oldest-first (folder names
    /// sort chronologically).
    nonisolated static func findPendingSessions(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        return entries
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return isDirectory
                    && fm.fileExists(atPath: SessionMeta.url(in: url).path)
                    && !fm.fileExists(atPath: RecordingArtifacts(recordingURL: url).transcriptJSON.path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Build the track list for a session folder. Offsets come from
    /// meta.json; a session that crashed before meta was written still
    /// transcribes, with zero offsets (tracks start within tens of
    /// milliseconds of each other anyway).
    nonisolated static func sessionTracks(for dir: URL) -> [WhisperEngine.SessionTrack] {
        let meta = try? SessionMeta.read(from: dir)
        let fm = FileManager.default

        func track(named name: String, fallback: String, speaker: Speaker) -> WhisperEngine.SessionTrack? {
            let filename = meta?.files[name] ?? fallback
            let url = dir.appendingPathComponent(filename)
            guard fm.fileExists(atPath: url.path) else { return nil }
            let offsetMs = meta?.startOffsetMs[name] ?? 0
            return WhisperEngine.SessionTrack(
                url: url,
                speaker: speaker,
                startOffset: TimeInterval(offsetMs) / 1000
            )
        }

        return [
            track(named: SessionMeta.systemTrack, fallback: RecordingSession.systemFilename, speaker: .remote),
            track(named: SessionMeta.micTrack, fallback: RecordingSession.micFilename, speaker: .user),
        ].compactMap { $0 }
    }

    private func drainQueueIfIdle() {
        guard !isDrainingQueue else { return }
        isDrainingQueue = true
        Task {
            while !pendingTranscriptions.isEmpty {
                let next = pendingTranscriptions.removeFirst()
                await performTranscription(audioURL: next)
            }
            isDrainingQueue = false
        }
    }

    /// Transcribe a recording (UI entry point). Routes through the serial
    /// queue so a manual tap and an auto-transcribe drain can't race — a
    /// direct call used to bypass the queue and could no-op a drained job,
    /// silently dropping it from the in-memory queue.
    func transcribe(audioURL: URL) {
        enqueue(audioURL)
    }

    /// The queue worker. Only `drainQueueIfIdle` calls this, and only one at a
    /// time, so it never overlaps itself — the `isTranscribing` guard is an
    /// invariant check, not a drop path.
    private func performTranscription(audioURL: URL) async {
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

                let segments: [TranscriptSegment]
                if RecordingArtifacts.isSessionDirectory(audioURL) {
                    // Session folder: transcribe mic/system tracks separately
                    // and merge by offset-aligned timestamps.
                    segments = try await engine.transcribeSession(
                        tracks: Self.sessionTracks(for: audioURL)
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.progress = progress
                        }
                    }
                } else {
                    // Legacy flat recording: stereo channel-split diarization.
                    segments = try await engine.transcribeDiarized(audioURL: audioURL) { [weak self] progress in
                        Task { @MainActor in
                            self?.progress = progress
                        }
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

            // Save markdown + JSON next to the recording's other artifacts
            let artifacts = RecordingArtifacts(recordingURL: transcript.recordingURL)
            try result.toMarkdown().write(to: artifacts.summaryMarkdown, atomically: true, encoding: .utf8)

            let encoded = try JSONEncoder().encode(result)
            try encoded.write(to: artifacts.summaryJSON, options: .atomic)

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
        streamingTranscriber.pause()
    }

    /// Resume live transcription — continue processing from where we left off
    func resumeLiveTranscription() async {
        streamingTranscriber.resume()
    }
}
