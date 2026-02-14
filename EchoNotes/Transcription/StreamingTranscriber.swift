import Foundation
@preconcurrency import AVFoundation
import os

/// Transcribes audio in near-real-time during recording by processing chunks through Whisper.
///
/// Fed raw 48kHz mono Float32 samples (system audio), resamples to 16kHz,
/// accumulates ~30-second chunks, and runs inference on each chunk.
/// Results are published as segments with correct time offsets.
@MainActor
final class StreamingTranscriber: ObservableObject {
    @Published var segments: [TranscriptSegment] = []
    @Published var isProcessing = false
    @Published var error: String?

    /// How many seconds of audio to accumulate before running inference.
    private let chunkDurationSeconds: Double = 30.0

    private var whisperEngine: WhisperEngine?
    private var converter: AVAudioConverter?
    private var pendingSamples: [Float] = [] // 48kHz mono
    private var chunkIndex: Int = 0
    private var processingTask: Task<Void, Never>?
    private let sampleRate: Double = 48000
    private let whisperSampleRate: Double = 16000

    /// Prepare the transcriber with a loaded Whisper engine.
    func prepare(engine: WhisperEngine) {
        self.whisperEngine = engine
        setupConverter()
    }

    /// Feed system audio samples (48kHz mono Float32) from the recording.
    /// Called from the audio capture callback — must be fast.
    nonisolated func feedSamples(_ samples: [Float]) {
        Task { @MainActor in
            self.pendingSamples.append(contentsOf: samples)

            let samplesNeeded = Int(chunkDurationSeconds * sampleRate)
            if self.pendingSamples.count >= samplesNeeded {
                self.processNextChunk()
            }
        }
    }

    /// Process any remaining audio when recording stops.
    func flush() {
        guard !pendingSamples.isEmpty else { return }
        processNextChunk()
    }

    /// Reset all state for a new recording.
    func reset() {
        processingTask?.cancel()
        processingTask = nil
        segments = []
        pendingSamples = []
        chunkIndex = 0
        isProcessing = false
        error = nil
    }

    // MARK: - Private

    private func setupConverter() {
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: whisperSampleRate,
            channels: 1,
            interleaved: false
        )!
        converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
    }

    private func processNextChunk() {
        guard whisperEngine != nil, !isProcessing else { return }

        // Grab all pending samples
        let chunk = pendingSamples
        pendingSamples = []
        let currentChunkIndex = chunkIndex
        chunkIndex += 1

        isProcessing = true

        processingTask = Task {
            do {
                let resampled = try resampleTo16kHz(chunk)
                let timeOffset = Double(currentChunkIndex) * chunkDurationSeconds

                guard let engine = whisperEngine else { return }

                let newSegments = try await engine.transcribeSamples(resampled)

                // Offset segment times to match position in the full recording
                let offsetSegments = newSegments.map { segment in
                    TranscriptSegment(
                        startTime: segment.startTime + timeOffset,
                        endTime: segment.endTime + timeOffset,
                        text: segment.text
                    )
                }

                segments.append(contentsOf: offsetSegments)
            } catch {
                self.error = "Live transcription error: \(error.localizedDescription)"
            }

            isProcessing = false
        }
    }

    /// Resample 48kHz mono samples to 16kHz for Whisper.
    private func resampleTo16kHz(_ samples: [Float]) throws -> [Float] {
        guard let converter else { throw WhisperError.audioConversionFailed }

        let sourceFormat = converter.inputFormat
        let targetFormat = converter.outputFormat

        let frameCount = AVAudioFrameCount(samples.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw WhisperError.audioConversionFailed
        }
        inputBuffer.frameLength = frameCount

        // Copy samples into the input buffer
        if let channelData = inputBuffer.floatChannelData {
            samples.withUnsafeBufferPointer { ptr in
                channelData[0].update(from: ptr.baseAddress!, count: samples.count)
            }
        }

        let ratio = whisperSampleRate / sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(samples.count) * ratio) + 256
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            throw WhisperError.audioConversionFailed
        }

        var hasData = true
        var convError: NSError?
        converter.convert(to: outputBuffer, error: &convError) { _, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return inputBuffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if let convError { throw convError }

        guard let channelData = outputBuffer.floatChannelData else {
            throw WhisperError.audioConversionFailed
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }
}
