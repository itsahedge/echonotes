@preconcurrency import AVFoundation
import os

/// Captures microphone audio using AVAudioEngine.
/// Outputs mono Float32 PCM at the requested sample rate.
final class MicrophoneCapture: @unchecked Sendable {
    var onBuffer: ((TimestampedBuffer) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat!
    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)

    func startCapture(sampleRate: Double = 48000) throws {
        guard _isCapturing.withLock({ !$0 }) else { return }

        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw MicrophoneError.noInputDevice }

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        guard converter != nil else { throw MicrophoneError.converterCreationFailed }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.processBuffer(buffer, time: time)
        }

        engine.prepare()
        try engine.start()
        _isCapturing.withLock { $0 = true }
    }

    func stopCapture() {
        guard _isCapturing.withLock({ $0 }) else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        _isCapturing.withLock { $0 = false }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let converter, let targetFormat else { return }

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
            print("Mic audio conversion error: \(error)")
            return
        }
        guard let channelData = outputBuffer.floatChannelData else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))

        onBuffer?(TimestampedBuffer(samples: samples, source: .microphone))
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
