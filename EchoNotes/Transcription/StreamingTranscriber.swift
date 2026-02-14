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
    let chunkDurationSeconds: Double = 30.0

    private var whisperEngine: WhisperEngine?
    private var pendingSamples: [Float] = [] // 48kHz mono
    private var totalSamplesProcessed: Int = 0 // Track actual position for time offsets
    private var processingTask: Task<Void, Never>?
    private var queuedChunks: [[Float]] = [] // Chunks waiting to be processed
    let sampleRate: Double = 48000
    private let whisperSampleRate: Double = 16000

    /// Prepare the transcriber with a loaded Whisper engine.
    func prepare(engine: WhisperEngine) {
        self.whisperEngine = engine
    }

    /// Feed system audio samples (48kHz mono Float32) from the recording.
    /// Called from the audio capture callback — must be fast.
    nonisolated func feedSamples(_ samples: [Float]) {
        Task { @MainActor in
            self.pendingSamples.append(contentsOf: samples)

            let samplesNeeded = Int(chunkDurationSeconds * sampleRate)
            if self.pendingSamples.count >= samplesNeeded {
                self.enqueueChunk()
            }
        }
    }

    /// Process any remaining audio when recording stops.
    /// Waits for any in-progress chunk to finish, then processes the remainder.
    func flush() async {
        // Wait for current processing to finish
        if let task = processingTask {
            await task.value
        }

        // Enqueue any remaining samples
        if !pendingSamples.isEmpty {
            enqueueChunk()
        }

        // Process remaining queued chunks
        if let task = processingTask {
            await task.value
        }
    }

    /// Reset all state for a new recording.
    func reset() {
        processingTask?.cancel()
        processingTask = nil
        segments = []
        pendingSamples = []
        queuedChunks = []
        totalSamplesProcessed = 0
        isProcessing = false
        error = nil
    }

    // MARK: - Private

    /// Move pending samples into the processing queue and kick off processing.
    private func enqueueChunk() {
        guard !pendingSamples.isEmpty else { return }
        queuedChunks.append(pendingSamples)
        pendingSamples = []
        processNextIfIdle()
    }

    /// Start processing the next queued chunk if not already busy.
    private func processNextIfIdle() {
        guard !isProcessing, !queuedChunks.isEmpty, whisperEngine != nil else { return }

        let chunk = queuedChunks.removeFirst()
        let sampleOffset = totalSamplesProcessed
        totalSamplesProcessed += chunk.count

        isProcessing = true

        processingTask = Task {
            do {
                let resampled = try Self.resampleTo16kHz(
                    chunk,
                    sourceSampleRate: sampleRate,
                    targetSampleRate: whisperSampleRate
                )
                let timeOffset = Double(sampleOffset) / sampleRate

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

            // Process next queued chunk if any
            processNextIfIdle()
        }
    }

    /// Resample mono samples to 16kHz for Whisper.
    /// Creates a fresh converter each time to avoid state leakage between chunks.
    nonisolated static func resampleTo16kHz(
        _ samples: [Float],
        sourceSampleRate: Double,
        targetSampleRate: Double
    ) throws -> [Float] {
        guard !samples.isEmpty else { return [] }

        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        )!
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw WhisperError.audioConversionFailed
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw WhisperError.audioConversionFailed
        }
        inputBuffer.frameLength = frameCount

        if let channelData = inputBuffer.floatChannelData {
            samples.withUnsafeBufferPointer { ptr in
                channelData[0].update(from: ptr.baseAddress!, count: samples.count)
            }
        }

        let ratio = targetSampleRate / sourceSampleRate
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
