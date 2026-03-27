@preconcurrency import AVFoundation
import AppKit
import os

/// Captures microphone audio using AVAudioEngine.
/// Outputs mono Float32 PCM at the requested sample rate.
/// Handles microphone disconnection gracefully by continuing to capture with silence.
final class MicrophoneCapture: @unchecked Sendable {
    var onBuffer: ((SourcedAudioBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    var onWarning: ((String) -> Void)?
    var hasWarning: Bool { _hasWarning.withLock { $0 } }
    
    static func availableDevices() -> [String] {
        // Return default microphone or empty array
        // macOS audio device enumeration requires AudioToolbox
        return []
    }

    func clearWarning() {
        _hasWarning.withLock { $0 = false }
    }

    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let _hasWarning = OSAllocatedUnfairLock(initialState: false)
    private let _isDisconnected = OSAllocatedUnfairLock(initialState: false)
    private let _pendingResume = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.echonotes", category: "MicrophoneCapture")
    private var configObserver: NSObjectProtocol?
    private var silenceTimer: DispatchSourceTimer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var capturedSampleRate: Double = AudioConfig.sampleRate

    func startCapture(sampleRate: Double = AudioConfig.sampleRate) throws {
        guard _isCapturing.withLock({ !$0 }) else { return }
        capturedSampleRate = sampleRate
        installSleepWakeObservers()

        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

        // Store target format early for future recovery attempts
        lock.lock()
        targetFormat = fmt
        lock.unlock()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // No input device — start in disconnected state with silence feed
        if inputFormat.sampleRate <= 0 {
            _hasWarning.withLock { $0 = true }
            _isDisconnected.withLock { $0 = true }
            _isCapturing.withLock { $0 = true }
            logger.warning("No microphone input device - recording will continue with system audio only")
            onWarning?("No microphone input device - recording will continue with system audio only")
            startSilenceFeed()
            return
        }

        let conv = AVAudioConverter(from: inputFormat, to: fmt)
        guard conv != nil else { throw MicrophoneError.converterCreationFailed }

        lock.lock()
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
            self.handleConfigurationChange()
        }

        engine.prepare()
        try engine.start()
        _isCapturing.withLock { $0 = true }
    }

    func stopCapture() {
        guard _isCapturing.withLock({ $0 }) else { return }

        _isCapturing.withLock { $0 = false }
        _pendingResume.withLock { $0 = false }
        removeSleepWakeObservers()

        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        // Stop silence timer if running
        if _isDisconnected.withLock({ $0 }) {
            silenceTimer?.cancel()
            silenceTimer = nil
            _isDisconnected.withLock { $0 = false }
        }

        guard engine.isRunning else {
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

    // MARK: - Configuration Change Handler

    private func handleConfigurationChange() {
        // Check if we're still capturing and engine stopped
        let wasCapturing = _isCapturing.withLock { current -> Bool in
            guard current else { return false }
            if !engine.isRunning {
                current = false
                return true
            }
            return false
        }

        guard wasCapturing else { return }

        // If already disconnected, try to recover (new device plugged in)
        if _isDisconnected.withLock({ $0 }) {
            attemptRecovery()
            return
        }

        // Engine stopped — attempt to restart with new/changed device
        logger.info("Microphone configuration changed, attempting to recover...")

        // Remove existing tap before restart
        engine.inputNode.removeTap(onBus: 0)

        // Try to restart
        if attemptRestart() {
            logger.info("Microphone recovered - now using new device")
            _hasWarning.withLock { $0 = false }
        } else {
            logger.warning("Failed to restart microphone - falling back to silence")
            handleDisconnection()
        }
    }

    // MARK: - Recovery Logic

    /// Attempts to restart the engine with the current input device.
    /// - Returns: true if restart succeeded
    private func attemptRestart() -> Bool {
        let deviceFormat = engine.inputNode.outputFormat(forBus: 0)
        guard deviceFormat.sampleRate > 0 else { return false }

        // Get target format (safe unwrap — set in startCapture before any path)
        lock.lock()
        guard let target = targetFormat else {
            lock.unlock()
            return false
        }
        lock.unlock()

        let conv = AVAudioConverter(from: deviceFormat, to: target)
        guard conv != nil else { return false }

        lock.lock()
        converter = conv
        lock.unlock()

        // Reinstall tap with new format
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: deviceFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        // Restart engine
        do {
            engine.prepare()
            try engine.start()
            return true
        } catch {
            logger.warning("Failed to restart engine: \(error.localizedDescription)")
            // Clean up tap if engine failed to start
            engine.inputNode.removeTap(onBus: 0)
            return false
        }
    }

    /// Attempts to recover from disconnection state when a new device appears
    private func attemptRecovery() {
        // Stop silence feed temporarily
        silenceTimer?.cancel()
        silenceTimer = nil

        // Remove any leftover tap
        engine.inputNode.removeTap(onBus: 0)

        if attemptRestart() {
            _isDisconnected.withLock { $0 = false }
            _hasWarning.withLock { $0 = false }
            logger.info("Microphone recovered - recording resumed with new device")
        } else {
            // Still no device — restart silence feed
            startSilenceFeed()
        }
    }

    /// Handles disconnection by starting silence feed
    private func handleDisconnection() {
        guard !_isDisconnected.withLock({ $0 }) else { return }

        _isDisconnected.withLock { $0 = true }
        _hasWarning.withLock { $0 = true }

        logger.warning("Microphone unavailable - recording will continue with system audio only")
        onWarning?("Microphone unavailable - recording will continue with system audio only")

        startSilenceFeed()
    }

    // MARK: - Sleep/Wake Handling

    /// Tear down the AVAudioEngine before sleep to prevent stale hardware references.
    /// On wake, create a fresh engine and restart capture if we were active.
    private func installSleepWakeObservers() {
        guard sleepObserver == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter

        sleepObserver = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let wasCapturing = self._isCapturing.withLock { $0 }
            guard wasCapturing else { return }
            self.logger.info("System going to sleep — tearing down AVAudioEngine")
            self._pendingResume.withLock { $0 = true }
            self._isCapturing.withLock { $0 = false }

            // Remove config observer to prevent spurious change notifications during sleep
            if let observer = self.configObserver {
                NotificationCenter.default.removeObserver(observer)
                self.configObserver = nil
            }

            // Stop silence timer if in disconnected mode
            if self._isDisconnected.withLock({ $0 }) {
                self.silenceTimer?.cancel()
                self.silenceTimer = nil
            }

            // Tear down the engine to prevent stale audio hardware references
            if self.engine.isRunning {
                self.engine.inputNode.removeTap(onBus: 0)
                self.engine.stop()
            }

            self.lock.lock()
            self.converter = nil
            self.lock.unlock()
        }

        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self._pendingResume.withLock({ $0 }) else { return }
            self.logger.info("System woke up — recreating AVAudioEngine")
            self._pendingResume.withLock { $0 = false }
            self._isDisconnected.withLock { $0 = false }

            // Replace the engine with a fresh instance to avoid stale hardware state
            self.engine = AVAudioEngine()

            // Brief delay for the audio subsystem to stabilize after wake
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                do {
                    try self.startCapture(sampleRate: self.capturedSampleRate)
                } catch {
                    self.logger.error("Failed to resume microphone after wake: \(error.localizedDescription)")
                    self.onError?(error)
                }
            }
        }
    }

    private func removeSleepWakeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        if let observer = sleepObserver {
            workspace.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = wakeObserver {
            workspace.removeObserver(observer)
            wakeObserver = nil
        }
    }

    // MARK: - Silence Feed

    /// Starts feeding silence buffers to onBuffer to keep stereo file synchronized.
    /// Uses DispatchSourceTimer for precise timing independent of RunLoop.
    private func startSilenceFeed() {
        let bufferSize = 4096
        let intervalMs = 85 // ~4096 samples at 48kHz ≈ 85ms per chunk

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMs), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, self._isCapturing.withLock({ $0 }) else { return }
            let silence = Array(repeating: Float(0.0), count: bufferSize)
            self.onBuffer?(SourcedAudioBuffer(samples: silence, source: .microphone))
        }
        timer.resume()
        silenceTimer = timer
    }

    // MARK: - Buffer Processing

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