import Foundation
import SwiftUI
import AppKit
import AVFoundation
import os

/// Central recording engine — coordinates system audio + mic capture and writes to file.
///
/// **Error Handling Strategy:**
/// - **Audio capture layer** (SystemAudioCapture, MicrophoneCapture): Uses closures (`onError`)
///   to propagate errors asynchronously from background threads.
/// - **Recording engine**: Surfaces errors via `@Published var errorMessage` for UI binding.
/// - **Transcription layer**: Uses throwing functions for synchronous errors, publishes async
///   errors via TranscriptionManager's `@Published var error`.
///
/// This mixed approach matches the concurrency model: audio callbacks need async propagation,
/// while engine state changes are published to UI observers, and transcription operations
/// use structured concurrency with throws.
@MainActor
final class RecordingEngine: ObservableObject {
    private let logger = Logger(subsystem: "com.echonotes", category: "RecordingEngine")
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0
    @Published var errorMessage: String?
    @Published var lastRecordingURL: URL?
    @AppStorage("autoTranscribe") var autoTranscribe = false
    @AppStorage("transcriptionMode") var transcriptionModeRaw: String = TranscriptionMode.postRecording.rawValue

    var transcriptionMode: TranscriptionMode {
        get { TranscriptionMode(rawValue: transcriptionModeRaw) ?? .postRecording }
        set { transcriptionModeRaw = newValue.rawValue }
    }

    let transcriptionManager = TranscriptionManager()

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicrophoneCapture()
    private var audioWriter: AudioFileWriter?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    /// Save location for recordings. Directory validation happens in startRecording().
    var saveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("EchoNotes", isDirectory: true)
    }

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil

        // Check permissions
        let permissions = PermissionChecker()
        if let permissionError = await permissions.checkPermissionsWithMessage() {
            errorMessage = permissionError
            return
        }

        // Ensure recordings directory exists
        do {
            try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Failed to create recordings directory: \(error.localizedDescription)"
            return
        }

        // Create output file
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "recording-\(timestamp).m4a"
        let fileURL = saveDirectory.appendingPathComponent(filename)

        do {
            // Set up audio file writer (M4A/AAC, 48kHz stereo — system L, mic R)
            let writer = try AudioFileWriter(outputURL: fileURL, sampleRate: AudioConfig.sampleRate, channels: 2) { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "Recording error: \(error.localizedDescription)"
                    await self?.stopRecording()
                }
            }

            audioWriter = writer

            // Surface system audio capture errors to the UI
            systemCapture.onError = { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "System audio error: \(error.localizedDescription)"
                    await self?.stopRecording()
                }
            }

            // Set up live transcription if enabled
            let isLive = transcriptionMode == .live
            if isLive {
                do {
                    try await transcriptionManager.prepareForLiveTranscription()
                    transcriptionManager.streamingTranscriber.reset()
                } catch {
                    errorMessage = "Failed to prepare live transcription: \(error.localizedDescription)"
                    cleanup()
                    return
                }
            }

            // Start captures with callbacks that feed the writer
            systemCapture.onBuffer = { [weak self] buffer in
                self?.audioWriter?.writeSystemBuffer(buffer)
                // Feed system audio to streaming transcriber for live mode
                if isLive {
                    self?.transcriptionManager.streamingTranscriber.feedSamples(buffer.samples)
                }
                Task { @MainActor in
                    self?.systemLevel = SourcedAudioBuffer.rmsLevel(buffer.samples)
                }
            }

            micCapture.onBuffer = { [weak self] buffer in
                self?.audioWriter?.writeMicBuffer(buffer)
                Task { @MainActor in
                    self?.micLevel = SourcedAudioBuffer.rmsLevel(buffer.samples)
                }
            }

            try await systemCapture.startCapture(sampleRate: AudioConfig.sampleRate)
            do {
                try micCapture.startCapture(sampleRate: AudioConfig.sampleRate)
            } catch {
                // System capture already started — must stop it before bailing
                await systemCapture.stopCapture()
                throw error
            }

            recordingStartTime = Date()
            isRecording = true
            logger.info("Recording started: \(fileURL.lastPathComponent)")

            // Duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let start = self.recordingStartTime else { return }
                    self.duration = Date().timeIntervalSince(start)
                }
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            audioWriter?.finalize()
            cleanup()
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        durationTimer?.invalidate()
        durationTimer = nil

        await systemCapture.stopCapture()
        micCapture.stopCapture()
        audioWriter?.finalize()

        let url = audioWriter?.outputURL
        let recordedDuration = duration  // Capture before reset
        cleanup()

        isRecording = false
        duration = 0
        micLevel = 0
        systemLevel = 0

        if let url {
            lastRecordingURL = url
            logger.info("Recording stopped: \(url.lastPathComponent), duration: \(String(format: "%.1f", recordedDuration))s")

            if transcriptionMode == .live {
                // Finalize live transcription — flush remaining chunks
                await transcriptionManager.finalizeLiveTranscription(recordingURL: url)
            } else {
                transcriptionManager.reset()
                // Auto-transcribe if enabled (post-recording mode)
                if autoTranscribe {
                    Task { await transcriptionManager.transcribe(audioURL: url) }
                }
            }
        }
    }

    private func cleanup() {
        audioWriter = nil
        recordingStartTime = nil
    }
}
