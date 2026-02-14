@preconcurrency import AVFoundation
import os

/// Captures microphone audio using AVAudioEngine.
/// Outputs mono Float32 PCM at the requested sample rate.
final class MicrophoneCapture: @unchecked Sendable {
    var onBuffer: ((SourcedAudioBuffer) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.echonotes", category: "MicrophoneCapture")

    func startCapture(sampleRate: Double = AudioConfig.sampleRate) throws {
        guard _isCapturing.withLock({ !$0 }) else { return }

        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw MicrophoneError.noInputDevice }

        let conv = AVAudioConverter(from: inputFormat, to: fmt)
        guard conv != nil else { throw MicrophoneError.converterCreationFailed }

        lock.lock()
        targetFormat = fmt
        converter = conv
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        _isCapturing.withLock { $0 = true }
    }

    func stopCapture() {
        guard _isCapturing.withLock({ $0 }) else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        converter = nil
        targetFormat = nil
        lock.unlock()

        _isCapturing.withLock { $0 = false }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard let converter, let targetFormat else { lock.unlock(); return }
        lock.unlock()

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        var hasData = true
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if let error {
            logger.error("Mic audio conversion error: \(error.localizedDescription)")
            return
        }
        guard let channelData = outputBuffer.floatChannelData else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))

        onBuffer?(SourcedAudioBuffer(samples: samples, source: .microphone))
    }
}

enum MicrophoneError: LocalizedError {
    case noInputDevice, converterCreationFailed
    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone found."
        case .converterCreationFailed: return "Failed to create audio converter."
        }
    }
}
