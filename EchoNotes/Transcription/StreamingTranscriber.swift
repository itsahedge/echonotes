import Foundation
@preconcurrency import AVFoundation

/// Transcribes audio in near-real-time during recording by processing chunks through Whisper.
///
/// Fed raw 48kHz mono Float32 samples (system audio), resamples to 16kHz,
/// accumulates ~5-second chunks, and runs inference on each chunk.
/// Results are published as segments with correct time offsets.
@MainActor
final class StreamingTranscriber: ObservableObject {
    @Published var segments: [TranscriptSegment] = []
    @Published var isProcessing = false
    @Published var error: String?

    /// Seconds of audio to accumulate before running inference.
    /// 5s gives fast feedback; Whisper base.en processes this in <1s on M-series.
    private let chunkSeconds: Double = 5.0

    private var whisperEngine: WhisperEngine?
    private var pendingSamples: [Float] = []
    private var totalSamplesProcessed: Int = 0
    private var processingTask: Task<Void, Never>?
    private let sampleRate: Double = 48000
    private let whisperRate: Double = 16000

    func prepare(engine: WhisperEngine) {
        self.whisperEngine = engine
    }

    /// Feed system audio samples from the recording callback.
    nonisolated func feedSamples(_ samples: [Float]) {
        Task { @MainActor in
            self.pendingSamples.append(contentsOf: samples)
            if self.pendingSamples.count >= Int(self.chunkSeconds * self.sampleRate) {
                self.processChunk()
            }
        }
    }

    /// Flush remaining audio when recording stops.
    func flush() async {
        if let task = processingTask { await task.value }
        if !pendingSamples.isEmpty { processChunk() }
        if let task = processingTask { await task.value }
    }

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        segments = []
        pendingSamples = []
        totalSamplesProcessed = 0
        isProcessing = false
        error = nil
    }

    // MARK: - Private

    private func processChunk() {
        guard !isProcessing, !pendingSamples.isEmpty, whisperEngine != nil else { return }

        let chunk = pendingSamples
        pendingSamples = []
        let timeOffset = Double(totalSamplesProcessed) / sampleRate
        totalSamplesProcessed += chunk.count
        isProcessing = true

        processingTask = Task {
            defer { isProcessing = false }
            do {
                let resampled = try resample(chunk)
                guard let engine = whisperEngine else { return }
                let newSegments = try await engine.transcribeSamples(resampled)

                segments.append(contentsOf: newSegments.map {
                    TranscriptSegment(
                        startTime: $0.startTime + timeOffset,
                        endTime: $0.endTime + timeOffset,
                        text: $0.text
                    )
                })
            } catch {
                self.error = "Live transcription error: \(error.localizedDescription)"
            }
        }
    }

    /// Resample 48kHz → 16kHz mono for Whisper.
    nonisolated private func resample(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else { return [] }

        let srcFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let dstFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: whisperRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: srcFmt, to: dstFmt) else {
            throw WhisperError.audioConversionFailed
        }

        let inBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(samples.count))!
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            inBuf.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }

        let outFrames = AVAudioFrameCount(Double(samples.count) * whisperRate / sampleRate) + 256
        let outBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: outFrames)!

        var fed = false
        var err: NSError?
        converter.convert(to: outBuf, error: &err) { _, status in
            if !fed { fed = true; status.pointee = .haveData; return inBuf }
            status.pointee = .noDataNow; return nil
        }
        if let err { throw err }

        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
    }
}
