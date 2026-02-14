import AVFoundation

/// A timestamped audio buffer from either system audio or microphone.
struct TimestampedBuffer: Sendable {
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

    /// Called on write errors (e.g. disk full). After an error, no further writes are accepted.
    var onError: ((Error) -> Void)?

    private let file: AVAudioFile
    private let sampleRate: Double
    private let format: AVAudioFormat
    private let lock = NSLock()

    // Accumulate samples from each source, flush when we have both.
    // Offset-based to avoid O(n) shifts — compacts periodically.
    private var systemSamples: [Float] = []
    private var systemOffset: Int = 0
    private var micSamples: [Float] = []
    private var micOffset: Int = 0
    private var writeError: Error?

    init(outputURL: URL, sampleRate: Double = 48000, channels: UInt32 = 2) throws {
        self.outputURL = outputURL
        self.sampleRate = sampleRate

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

    func writeSystemBuffer(_ buffer: TimestampedBuffer) {
        lock.lock()
        guard writeError == nil else { lock.unlock(); return }
        systemSamples.append(contentsOf: buffer.samples)
        flushIfReady()
        lock.unlock()
    }

    func writeMicBuffer(_ buffer: TimestampedBuffer) {
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

        // Compact when fully consumed to free memory
        if systemOffset == systemSamples.count {
            systemSamples.removeAll(keepingCapacity: true)
            systemOffset = 0
        } else if systemOffset > 48000 {
            // Compact periodically to avoid unbounded growth
            systemSamples.removeFirst(systemOffset)
            systemOffset = 0
        }
        if micOffset == micSamples.count {
            micSamples.removeAll(keepingCapacity: true)
            micOffset = 0
        } else if micOffset > 48000 {
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
    func finalize() {
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
    var errorDescription: String? { "Failed to create audio format." }
}
