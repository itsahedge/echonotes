@preconcurrency import AVFoundation
import os

/// Captures microphone audio using AVAudioEngine.
/// Outputs mono Float32 PCM at the requested sample rate.
final class MicrophoneCapture: @unchecked Sendable {
    var onBuffer: ((SourcedAudioBuffer) -> Void)?
    var onError: ((Error) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.echonotes", category: "MicrophoneCapture")
    private var configObserver: NSObjectProtocol?

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

        // Monitor for configuration changes (device disconnect, etc.)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Check if engine stopped unexpectedly
            if !self.engine.isRunning && self._isCapturing.withLock({ $0 }) {
                let error = MicrophoneError.deviceDisconnected
                self.logger.error("Microphone configuration changed, engine stopped: \(error.localizedDescription)")
                self._isCapturing.withLock { $0 = false }
                self.onError?(error)
            }
        }

        engine.prepare()
        try engine.start()
        _isCapturing.withLock { $0 = true }
    }

    func stopCapture() {
        guard _isCapturing.withLock({ $0 }) else { return }
        
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        
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
    case noInputDevice, converterCreationFailed, deviceDisconnected
    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone found."
        case .converterCreationFailed: return "Failed to create audio converter."
        case .deviceDisconnected: return "Microphone disconnected during recording."
        }
    }
}
