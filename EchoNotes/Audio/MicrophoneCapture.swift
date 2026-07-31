@preconcurrency import AVFoundation
import AppKit
import os

/// Captures the default microphone via AVAudioEngine, downmixing to 48kHz
/// mono and streaming AAC into a CAF file.
///
/// A fresh AVAudioEngine is built for every capture start and resume —
/// reusing one engine across sleep/wake or device changes leaves it holding
/// stale hardware references, which caused post-sleep crashes in earlier
/// builds.
///
/// If the device disappears mid-recording, timed silence is written so this
/// track's timeline stays aligned with the system track; capture recovers
/// automatically when a device returns.
final class MicrophoneCapture: @unchecked Sendable {
    /// 48kHz mono samples for level metering. Called off the main thread.
    var onBuffer: ((SourcedAudioBuffer) -> Void)?
    /// Called once on the first unrecoverable file-write error.
    var onError: ((Error) -> Void)?
    /// Non-fatal problems (device missing/disconnected); recording continues.
    var onWarning: ((String) -> Void)?
    var hasWarning: Bool { _hasWarning.withLock { $0 } }

    /// Wall-clock time of the first captured buffer — the track's true start,
    /// used to offset-align the two tracks' transcript timestamps.
    var firstBufferAt: Date? { _firstBufferAt.withLock { $0 } }

    static func availableDevices() -> [String] {
        // Device selection not implemented — the default input is used.
        []
    }

    func clearWarning() {
        _hasWarning.withLock { $0 = false }
    }

    private var engine: AVAudioEngine?
    /// Guards `file`, `converter`, and `targetFormat` across the render
    /// thread, the silence timer queue, and the main thread.
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var configObserver: NSObjectProtocol?
    private var silenceTimer: DispatchSourceTimer?

    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let _isPaused = OSAllocatedUnfairLock(initialState: false)
    private let _hasWarning = OSAllocatedUnfairLock(initialState: false)
    private let _isDisconnected = OSAllocatedUnfairLock(initialState: false)
    private let _firstBufferAt = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private let _writeFailed = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.echonotes", category: "MicrophoneCapture")

    /// Start capturing the mic into `url` (use a .caf extension).
    func start(writingTo url: URL) throws {
        guard _isCapturing.withLock({ !$0 }) else { return }
        _firstBufferAt.withLock { $0 = nil }
        _writeFailed.withLock { $0 = false }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioConfig.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw MicrophoneError.converterCreationFailed
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: target.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let newFile: AVAudioFile
        do {
            newFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: target.commonFormat,
                interleaved: target.isInterleaved
            )
        } catch {
            throw MicrophoneError.fileCreationFailed(error)
        }

        lock.lock()
        file = newFile
        targetFormat = target
        lock.unlock()

        do {
            try attachEngine()
        } catch {
            lock.lock()
            file = nil
            targetFormat = nil
            lock.unlock()
            throw error
        }
        _isCapturing.withLock { $0 = true }
    }

    /// Tear the engine down but keep the file open — resumable.
    func pauseCapture() {
        guard _isCapturing.withLock({ $0 }), _isPaused.withLock({ !$0 }) else { return }
        _isPaused.withLock { $0 = true }
        tearDownEngine()
    }

    /// Rebuild a fresh engine after a pause. Falls back to the silence feed
    /// (with a warning) if no input device is available.
    ///
    /// `_isPaused` is cleared only after `attachEngine()` succeeds: if it
    /// throws (converter creation or engine start failing right after wake),
    /// the track stays `paused` so a later resume can retry, instead of being
    /// left capturing-but-dead with no engine and no silence feed.
    func resumeCapture() throws {
        guard _isCapturing.withLock({ $0 }), _isPaused.withLock({ $0 }) else { return }
        try attachEngine()
        _isPaused.withLock { $0 = false }
    }

    /// Stop capturing and close the file. Idempotent.
    func stopCapture() {
        guard _isCapturing.withLock({ $0 }) else { return }
        _isCapturing.withLock { $0 = false }
        _isPaused.withLock { $0 = false }
        tearDownEngine()

        lock.lock()
        file = nil
        targetFormat = nil
        lock.unlock()
    }

    // MARK: - Engine lifecycle

    /// Build a fresh engine + converter and start capture, or enter the
    /// silence-feed state when no input device exists.
    private func attachEngine() throws {
        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // No input device — keep the track's timeline advancing with silence.
        guard inputFormat.sampleRate > 0 else {
            engine = newEngine
            enterDisconnectedState(
                warning: "No microphone input device - recording will continue with system audio only"
            )
            return
        }

        lock.lock()
        let target = targetFormat
        lock.unlock()
        guard let target, let conv = AVAudioConverter(from: inputFormat, to: target) else {
            throw MicrophoneError.converterCreationFailed
        }

        lock.lock()
        converter = conv
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            removeConfigObserver()
            lock.lock()
            converter = nil
            lock.unlock()
            throw error
        }
        engine = newEngine
        _isDisconnected.withLock { $0 = false }
    }

    /// Stop the engine and all supporting machinery. Leaves the file alone.
    private func tearDownEngine() {
        removeConfigObserver()
        silenceTimer?.cancel()
        silenceTimer = nil
        _isDisconnected.withLock { $0 = false }

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
        }
        engine = nil

        lock.lock()
        converter = nil
        lock.unlock()
    }

    private func removeConfigObserver() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
    }

    // MARK: - Device change handling

    /// The engine's I/O configuration changed (device unplugged, switched,
    /// or reappeared). Rebuild from scratch — a fresh engine is the only
    /// reliable way back to a good state.
    private func handleConfigurationChange() {
        guard _isCapturing.withLock({ $0 }), _isPaused.withLock({ !$0 }) else { return }
        logger.info("Microphone configuration changed, rebuilding engine...")

        tearDownEngine()
        do {
            try attachEngine()
            if !_isDisconnected.withLock({ $0 }) {
                _hasWarning.withLock { $0 = false }
                logger.info("Microphone recovered — capture rebuilt with current device")
            }
        } catch {
            logger.warning("Failed to rebuild microphone capture: \(error.localizedDescription)")
            enterDisconnectedState(
                warning: "Microphone unavailable - recording will continue with system audio only"
            )
        }
    }

    private func enterDisconnectedState(warning: String) {
        guard !_isDisconnected.withLock({ $0 }) else { return }
        _isDisconnected.withLock { $0 = true }
        _hasWarning.withLock { $0 = true }
        logger.warning("\(warning)")
        onWarning?(warning)
        startSilenceFeed()
    }

    // MARK: - Silence feed

    /// Feeds timed silence into the file and level meter while no device is
    /// available, so the mic track's timeline stays aligned with the system
    /// track. Uses DispatchSourceTimer for timing independent of the RunLoop.
    private func startSilenceFeed() {
        let bufferSize = 4096
        let intervalMs = 85 // ~4096 samples at 48kHz ≈ 85ms per chunk

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMs), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self,
                  self._isDisconnected.withLock({ $0 }),
                  !self._isPaused.withLock({ $0 })
            else { return }

            self.lock.lock()
            let file = self.file
            let target = self.targetFormat
            self.lock.unlock()
            guard let file, let target else { return }

            self._firstBufferAt.withLock { if $0 == nil { $0 = Date() } }

            if let silence = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(bufferSize)) {
                silence.frameLength = AVAudioFrameCount(bufferSize)
                // Buffers start zero-filled; write as-is.
                do {
                    try file.write(from: silence)
                } catch {
                    self.reportWriteFailure(error)
                    return
                }
            }
            self.onBuffer?(SourcedAudioBuffer(
                samples: [Float](repeating: 0, count: bufferSize),
                source: .microphone
            ))
        }
        timer.resume()
        silenceTimer = timer
    }

    // MARK: - Buffer processing (render thread)

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !_writeFailed.withLock({ $0 }) else { return }

        lock.lock()
        let converter = self.converter
        let target = self.targetFormat
        let file = self.file
        lock.unlock()
        guard let converter, let target, let file else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputFrameCount) else {
            return
        }

        var error: NSError?
        let didProvideInput = OSAllocatedUnfairLock(initialState: false)
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            let shouldProvideInput = didProvideInput.withLock { hasProvidedInput in
                guard !hasProvidedInput else { return false }
                hasProvidedInput = true
                return true
            }
            if shouldProvideInput {
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        if let error {
            logger.error("Mic audio conversion error: \(error.localizedDescription)")
            return
        }

        _firstBufferAt.withLock { if $0 == nil { $0 = Date() } }

        do {
            try file.write(from: outputBuffer)
        } catch {
            reportWriteFailure(error)
            return
        }

        guard onBuffer != nil, let channelData = outputBuffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        onBuffer?(SourcedAudioBuffer(samples: samples, source: .microphone))
    }

    private func reportWriteFailure(_ error: Error) {
        let firstFailure = _writeFailed.withLock { failed -> Bool in
            guard !failed else { return false }
            failed = true
            return true
        }
        guard firstFailure else { return }
        logger.error("Mic track write failed: \(error.localizedDescription)")
        onError?(error)
    }
}

enum MicrophoneError: LocalizedError {
    case converterCreationFailed
    case fileCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .converterCreationFailed: return "Failed to create audio converter."
        case .fileCreationFailed(let e): return "Failed to create the mic audio file: \(e.localizedDescription)"
        }
    }
}
