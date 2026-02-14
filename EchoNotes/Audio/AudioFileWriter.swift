import AVFoundation
import os

/// An audio buffer with its source (system audio or microphone).
struct SourcedAudioBuffer: Sendable {
    let samples: [Float]
    let source: AudioSource

    enum AudioSource: Sendable {
        case system
        case microphone
    }

    /// Calculate RMS level for visualization.
    static func rmsLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }
}

/// Writes system audio and mic audio into a single M4A file.
/// System audio goes to the left channel, mic to the right channel.
/// This preserves both streams for future processing while producing a single file.
final class AudioFileWriter: @unchecked Sendable {
    let outputURL: URL

    /// Called on write errors (e.g. disk full, buffer overflow). After an error, no further writes are accepted.
    let onError: (@Sendable (Error) -> Void)?

    private let file: AVAudioFile
    private let sampleRate: Double
    private let format: AVAudioFormat
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.echonotes", category: "AudioFileWriter")

    /// Maximum samples one source can buffer ahead of the other (10 seconds at sample rate).
    /// Prevents OOM if one source stops sending data.
    private let maxBufferLag: Int

    // Accumulate samples from each source, flush when we have both.
    // Offset-based to avoid O(n) shifts — compacts periodically.
    private var systemSamples: [Float] = []
    private var systemOffset: Int = 0
    private var micSamples: [Float] = []
    private var micOffset: Int = 0
    private var writeError: Error?

    /// Tracks in-flight write callbacks so finalize() can wait for them to complete.
    private let inflightGroup = DispatchGroup()

    init(outputURL: URL, sampleRate: Double = AudioConfig.sampleRate, channels: UInt32 = 2, onError: (@Sendable (Error) -> Void)? = nil) throws {
        self.outputURL = outputURL
        self.sampleRate = sampleRate
        self.onError = onError
        self.maxBufferLag = Int(sampleRate) * 10 // 10 seconds

        // Stereo interleaved format for the output file
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            throw WriterError.formatCreationFailed
        }
        self.format = fmt

        // Create output file (M4A with AAC encoding for compression)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        self.file = try AVAudioFile(forWriting: outputURL, settings: settings)
    }

    func writeSystemBuffer(_ buffer: SourcedAudioBuffer) {
        inflightGroup.enter()
        defer { inflightGroup.leave() }
        lock.lock()
        guard writeError == nil else { lock.unlock(); return }
        systemSamples.append(contentsOf: buffer.samples)
        flushIfReady()
        lock.unlock()
    }

    func writeMicBuffer(_ buffer: SourcedAudioBuffer) {
        inflightGroup.enter()
        defer { inflightGroup.leave() }
        lock.lock()
        guard writeError == nil else { lock.unlock(); return }
        micSamples.append(contentsOf: buffer.samples)
        flushIfReady()
        lock.unlock()
    }

    /// Write interleaved stereo whenever we have enough from both sources.
    private func flushIfReady() {
        let sysAvailable = systemSamples.count - systemOffset
        let micAvailable = micSamples.count - micOffset

        // Guard against unbounded buffer growth if one source stops sending data
        if sysAvailable > maxBufferLag || micAvailable > maxBufferLag {
            logger.error("Buffer overflow: system=\(sysAvailable) mic=\(micAvailable) max=\(self.maxBufferLag)")
            writeError = WriterError.bufferOverflow
            onError?(WriterError.bufferOverflow)
            return
        }

        let count = min(sysAvailable, micAvailable)
        guard count > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(count)

        guard let channelData = pcmBuffer.floatChannelData else { return }
        // Channel 0 = system (left), Channel 1 = mic (right)
        for i in 0..<count {
            channelData[0][i] = systemSamples[systemOffset + i]
            channelData[1][i] = micSamples[micOffset + i]
        }

        systemOffset += count
        micOffset += count

        // Compact when fully consumed or when offset exceeds 50% to prevent unbounded growth
        if systemOffset == systemSamples.count {
            systemSamples.removeAll(keepingCapacity: true)
            systemOffset = 0
        } else if systemOffset > systemSamples.count / 2 {
            systemSamples.removeFirst(systemOffset)
            systemOffset = 0
        }
        
        if micOffset == micSamples.count {
            micSamples.removeAll(keepingCapacity: true)
            micOffset = 0
        } else if micOffset > micSamples.count / 2 {
            micSamples.removeFirst(micOffset)
            micOffset = 0
        }

        do {
            try file.write(from: pcmBuffer)
        } catch {
            writeError = error
            onError?(error)
        }
    }

    /// Flush any remaining samples and close the file.
    ///
    /// **Known limitation:** There is a race window where capture callbacks may still be
    /// in-flight when finalize is called (after stopCapture but before callbacks complete).
    /// Samples arriving during this window may be dropped. A proper fix would require
    /// synchronization at the capture layer to ensure all callbacks have finished before
    /// finalize is invoked.
    func finalize() {
        // Wait for all in-flight write callbacks to complete before finalizing.
        inflightGroup.wait()
        lock.lock()
        guard writeError == nil else { lock.unlock(); return }
        // Pad the shorter stream with silence
        let sysRemaining = systemSamples.count - systemOffset
        let micRemaining = micSamples.count - micOffset
        let maxCount = max(sysRemaining, micRemaining)
        if maxCount > 0 {
            while (systemSamples.count - systemOffset) < maxCount { systemSamples.append(0) }
            while (micSamples.count - micOffset) < maxCount { micSamples.append(0) }
            flushIfReady()
        }
        lock.unlock()
    }
}

enum WriterError: LocalizedError {
    case formatCreationFailed
    case bufferOverflow

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Failed to create audio format."
        case .bufferOverflow: return "Audio source mismatch — one stream stopped sending data."
        }
    }
}
