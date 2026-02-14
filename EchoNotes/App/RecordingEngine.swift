import Foundation
import SwiftUI
import AppKit
import AVFoundation
import Combine

/// Central recording engine — coordinates system audio + mic capture and writes to file.
@MainActor
final class RecordingEngine: ObservableObject {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0
    @Published var errorMessage: String?
    @Published var lastRecordingURL: URL?
    @AppStorage("autoTranscribe") var autoTranscribe = false

    let transcriptionManager = TranscriptionManager()

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicrophoneCapture()
    private var audioWriter: AudioFileWriter?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    /// Save location for recordings.
    var saveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("EchoNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil

        // Check permissions
        let permissions = PermissionChecker()
        guard await permissions.ensureAllPermissions() else {
            errorMessage = "Microphone and Screen Recording permissions are required."
            return
        }

        // Create output file
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "recording-\(timestamp).m4a"
        let fileURL = saveDirectory.appendingPathComponent(filename)

        do {
            // Set up audio file writer (M4A/AAC, 48kHz stereo — system L, mic R)
            let writer = try AudioFileWriter(outputURL: fileURL, sampleRate: 48000, channels: 2)

            // Surface write errors (e.g. disk full) to the UI
            writer.onError = { [weak self] error in
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

            // Start captures with callbacks that feed the writer
            systemCapture.onBuffer = { [weak self] buffer in
                self?.audioWriter?.writeSystemBuffer(buffer)
                Task { @MainActor in
                    self?.systemLevel = TimestampedBuffer.rmsLevel(buffer.samples)
                }
            }

            micCapture.onBuffer = { [weak self] buffer in
                self?.audioWriter?.writeMicBuffer(buffer)
                Task { @MainActor in
                    self?.micLevel = TimestampedBuffer.rmsLevel(buffer.samples)
                }
            }

            try await systemCapture.startCapture(sampleRate: 48000)
            try micCapture.startCapture(sampleRate: 48000)

            recordingStartTime = Date()
            isRecording = true

            // Duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let start = self.recordingStartTime else { return }
                    self.duration = Date().timeIntervalSince(start)
                }
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            await cleanup()
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
        await cleanup()

        isRecording = false
        duration = 0
        micLevel = 0
        systemLevel = 0

        if let url {
            lastRecordingURL = url
            transcriptionManager.reset()
            print("Recording saved: \(url.path)")

            // Auto-transcribe if enabled
            if autoTranscribe {
                Task { await transcriptionManager.transcribe(audioURL: url) }
            }
        }
    }

    private func cleanup() async {
        audioWriter = nil
        recordingStartTime = nil
    }
}
