import Foundation
@preconcurrency import AVFoundation

/// Transcribes audio in near-real-time during recording by processing chunks through Whisper.
///
/// Fed raw 48kHz mono Float32 samples (system audio), resamples to 16kHz,
/// accumulates ~5-second chunks, and runs inference on each chunk.
/// Results are published as segments with correct time offsets.
///
/// Thread safety: `feedSamples` is called from audio callbacks on arbitrary threads.
/// Samples are serialized through a lock-protected buffer to guarantee ordering,
/// then drained on the MainActor for processing.
@MainActor
final class StreamingTranscriber: ObservableObject {
    @Published var segments: [TranscriptSegment] = []
    @Published var isProcessing = false
    @Published var error: String?

    /// Seconds of audio to accumulate before running inference.
    /// 5s gives fast feedback; Whisper base.en processes this in <1s on M-series.
    private let chunkSeconds: Double = 5.0

    private var whisperEngine: WhisperEngine?
    private var totalSamplesProcessed: Int = 0
    private var processingTask: Task<Void, Never>?
    private let sampleRate: Double = 48000
    private let whisperRate: Double = 16000

    /// Lock-protected incoming sample buffer. Written from audio callbacks,
    /// drained on MainActor. The lock guarantees FIFO ordering regardless
    /// of which thread the audio callback fires on.
    private nonisolated(unsafe) let sampleLock = NSLock()
    private nonisolated(unsafe) var incomingSamples: [Float] = []

    /// Reusable audio converter (48kHz → 16kHz). Created once in prepare()
    /// to avoid repeated allocation per chunk. Only read from nonisolated
    /// resample() after being set on MainActor — safe because prepare()
    /// is always called before any audio flows.
    private nonisolated(unsafe) var resampler: AVAudioConverter?
    private nonisolated(unsafe) let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    private nonisolated(unsafe) let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    func prepare(engine: WhisperEngine) {
        self.whisperEngine = engine
        self.resampler = AVAudioConverter(from: srcFormat, to: dstFormat)
    }

    /// Feed system audio samples from the recording callback.
    /// Thread-safe — can be called from any thread. Samples are appended
    /// in the exact order received, then drained on MainActor.
    nonisolated func feedSamples(_ samples: [Float]) {
        sampleLock.lock()
        incomingSamples.append(contentsOf: samples)
        let count = incomingSamples.count
        sampleLock.unlock()

        let threshold = Int(chunkSeconds * sampleRate)
        if count >= threshold {
            Task { @MainActor in
                self.drainAndProcess()
            }
        }
    }

    /// Flush remaining audio when recording stops.
    func flush() async {
        // Wait for any in-flight processing
        if let task = processingTask { await task.value }
        // Drain whatever remains
        drainAndProcess()
        if let task = processingTask { await task.value }
    }

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        segments = []
        totalSamplesProcessed = 0
        isProcessing = false
        error = nil
        
        // Clear queued samples — these are intentionally dropped on reset.
        // If you need to preserve in-flight audio, call flush() before reset().
        queuedSamples = []

        sampleLock.lock()
        incomingSamples = []
        sampleLock.unlock()
    }

    // MARK: - Private

    /// Move samples from the lock-protected buffer to the processing pipeline.
    /// Called on MainActor to safely update published state.
    private func drainAndProcess() {
        sampleLock.lock()
        let drained = incomingSamples
        incomingSamples.removeAll(keepingCapacity: true)
        sampleLock.unlock()

        guard !drained.isEmpty else { return }
        processChunk(drained)
    }

    /// Process a chunk of audio samples through Whisper.
    /// If already processing, appends to a queue that gets picked up after.
    private var queuedSamples: [Float] = []

    private func processChunk(_ samples: [Float]) {
        if isProcessing {
            // Queue instead of dropping — fixes issue #11
            queuedSamples.append(contentsOf: samples)
            return
        }

        let chunk = samples
        let timeOffset = Double(totalSamplesProcessed) / sampleRate
        totalSamplesProcessed += chunk.count
        isProcessing = true

        processingTask = Task {
            defer {
                isProcessing = false
                // Process any queued samples that arrived during inference
                if !queuedSamples.isEmpty {
                    let queued = queuedSamples
                    queuedSamples = []
                    processChunk(queued)
                }
            }
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

    /// Resample 48kHz → 16kHz mono for Whisper using the reusable converter.
    nonisolated private func resample(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard let converter = resampler else {
            throw WhisperError.audioConversionFailed
        }

        let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            inBuf.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }

        let outFrames = AVAudioFrameCount(Double(samples.count) * dstFormat.sampleRate / srcFormat.sampleRate) + 256
        let outBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outFrames)!

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
