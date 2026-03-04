@preconcurrency import AVFoundation
import os

/// Captures microphone audio using AVAudioEngine.
/// Outputs mono Float32 PCM at the requested sample rate.
/// Handles microphone disconnection gracefully by continuing to capture with silence.
final class MicrophoneCapture: @unchecked Sendable {
    var onBuffer: ((SourcedAudioBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    var onWarning: ((String) -> Void)?
    var hasWarning: Bool { _hasWarning.withLock { $0 } }

    func clearWarning() {
        _hasWarning.withLock { $0 = false }
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.echonotes", category: "MicrophoneCapture")
    private var configObserver: NSObjectProtocol?
    private var _hasWarning = OSAllocatedUnfairLock(initialState: false)
    private var isDisconnected = false
    private var silenceTimer: Timer?

    func startCapture(sampleRate: Double = AudioConfig.sampleRate) throws {
        guard _isCapturing.withLock({ !$0 }) else { return }

        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { 
            // No input device - start in disconnected state
            self._hasWarning.withLock { $0 = true }
            self.logger.warning("No microphone input device - recording will continue with system audio only")
            self.onWarning?("No microphone input device - recording will continue with system audio only")
            _isCapturing.withLock { $0 = true }
            return
        }

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
            // Atomically check and update _isCapturing to avoid races with stopCapture()
            let wasCapturing = self._isCapturing.withLock { current -> Bool in
                guard current else { return false }
                if !self.engine.isRunning {
                    current = false
                    return true
                }
                return false
            }
            guard wasCapturing else { return }
            
            // Check if we already have a silence feed running
            if self.isDisconnected {
                // Already in disconnected state - try to recover
                self.tryRecoverFromDisconnection()
                return
            }
            
            // Engine stopped due to config change - try to restart with new device
            self.logger.info("Microphone configuration changed, attempting to recover...")
            
            // Stop the tap first
            self.engine.inputNode.removeTap(onBus: 0)
            
            // Try to restart the engine with the new device
            let newFormat = self.engine.inputNode.outputFormat(forBus: 0)
            guard newFormat.sampleRate > 0 else {
                // No valid device available - fall back to silence
                self.handlePermanentDisconnection()
                return
            }
            
            // Update converter for new format
            self.lock.lock()
            let conv = AVAudioConverter(from: newFormat, to: self.targetFormat!)
            self.converter = conv
            self.lock.unlock()
            
            guard conv != nil else {
                self.handlePermanentDisconnection()
                return
            }
            
            // Reinstall tap with new format
            self.engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: newFormat) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }
            
            // Restart engine
            do {
                self.engine.prepare()
                try self.engine.start()
                self.logger.info("Microphone recovered - now using new device")
                // Clear warning state if it was set
                self._hasWarning.withLock { $0 = false }
            } catch {
                self.logger.warning("Failed to restart microphone: \(error.localizedDescription)")
                self.handlePermanentDisconnection()
            }
        }

        engine.prepare()
        try engine.start()
        _isCapturing.withLock { $0 = true }
    }

    func stopCapture() {
        guard _isCapturing.withLock({ $0 }) else { return }
        
        _isCapturing.withLock { $0 = false }
        
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        
        if isDisconnected {
            // Engine was stopped due to disconnection - stop the silence feed
            silenceTimer?.invalidate()
            silenceTimer = nil
            isDisconnected = false
        }
        
        guard engine.isRunning else {
            // Engine not running but not in disconnected state - cleanup and return
            lock.lock()
            converter = nil
            targetFormat = nil
            lock.unlock()
            return
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        converter = nil
        targetFormat = nil
        lock.unlock()
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
    
    /// Starts feeding silence buffers to onBuffer to keep stereo file synchronized
    private func startSilenceFeed() {
        // Feed silence at ~48kHz, matching the audio writer's expected rate
        // Using 4096-sample chunks to match the tap buffer size
        let bufferSize = 4096
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
            guard let self else { return }
            let silence = Array(repeating: Float(0.0), count: bufferSize)
            self.onBuffer?(SourcedAudioBuffer(samples: silence, source: .microphone))
        }
    }
    
    /// Called when engine stops due to config change and we need to fall back to silence
    private func handlePermanentDisconnection() {
        guard !isDisconnected else { return }
        isDisconnected = true
        _hasWarning.withLock { $0 = true }
        logger.warning("Microphone unavailable - recording will continue with system audio only")
        onWarning?("Microphone unavailable - recording will continue with system audio only")
        startSilenceFeed()
    }
    
    /// Attempts to recover from a disconnection by checking if a new device is available
    private func tryRecoverFromDisconnection() {
        // Stop the silence feed temporarily
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Check if we have a valid device now
        let newFormat = engine.inputNode.outputFormat(forBus: 0)
        guard newFormat.sampleRate > 0 else {
            // Still no device - restart silence feed
            startSilenceFeed()
            return
        }
        
        // Try to restart with new device
        lock.lock()
        let conv = AVAudioConverter(from: newFormat, to: targetFormat!)
        converter = conv
        lock.unlock()
        
        guard conv != nil else {
            startSilenceFeed()
            return
        }
        
        // Reinstall tap
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: newFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        
        // Restart engine
        do {
            engine.prepare()
            try engine.start()
            isDisconnected = false
            _hasWarning.withLock { $0 = false }
            logger.info("Microphone recovered - recording resumed with new device")
        } catch {
            logger.warning("Recovery failed: \(error.localizedDescription)")
            isDisconnected = true
            startSilenceFeed()
        }
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