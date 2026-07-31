import AVFoundation
import CoreAudio
import Foundation
import os

/// Captures all system audio output via a Core Audio process tap
/// (macOS 14.2+), streaming it straight into an AAC-in-CAF file.
///
/// No virtual device and no Screen Recording permission: the tap mixes every
/// process's output to stereo and hands us buffers through a private
/// aggregate device. First use triggers the one-time "System Audio Recording"
/// TCC prompt. This replaces the previous ScreenCaptureKit capture, whose
/// SCStream/XPC state had to be torn down and rebuilt around sleep — a
/// recurring source of post-sleep failures.
///
/// CAF on purpose: unlike m4a it needs no finalization pass, so a crash
/// mid-meeting loses nothing already written to disk.
final class SystemAudioCapture: @unchecked Sendable {
    /// Downmixed 48kHz mono samples for level metering and live transcription.
    /// Called on the capture queue — must be thread-safe.
    var onBuffer: ((SourcedAudioBuffer) -> Void)?
    /// Called once on the first unrecoverable file-write error.
    var onError: ((Error) -> Void)?

    /// Wall-clock time of the first captured buffer — the track's true start,
    /// used to offset-align the two tracks' transcript timestamps.
    var firstBufferAt: Date? { _firstBufferAt.withLock { $0 } }

    static func availableDevices() -> [String] {
        // System audio has no selectable devices — the tap covers everything.
        []
    }

    enum CaptureError: LocalizedError {
        case tapCreationFailed(OSStatus)
        case tapFormatUnreadable(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case fileCreationFailed(Error)
        case formatCreationFailed

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let s):
                return "System audio tap creation failed (OSStatus \(s)). "
                    + "Enable EchoNotes under System Settings → Privacy & Security → "
                    + "Screen & System Audio Recording → System Audio Recording Only, then try again."
            case .tapFormatUnreadable(let s):
                return "Couldn't read the system audio format (OSStatus \(s))."
            case .aggregateCreationFailed(let s):
                return "Audio device setup failed (OSStatus \(s))."
            case .ioProcCreationFailed(let s):
                return "Audio callback setup failed (OSStatus \(s))."
            case .deviceStartFailed(let s):
                return "Couldn't start system audio capture (OSStatus \(s))."
            case .fileCreationFailed(let e):
                return "Couldn't create the system audio file: \(e.localizedDescription)"
            case .formatCreationFailed:
                return "Couldn't create the system audio processing format."
            }
        }
    }

    private let logger = Logger(subsystem: "com.echonotes", category: "SystemAudioCapture")
    /// Serial queue that receives IO proc callbacks and owns `file`/`converter`
    /// once capture is running.
    private let queue = DispatchQueue(label: "com.echonotes.system-tap")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    /// Converts tap-format buffers to 48kHz mono for `onBuffer` consumers.
    /// Nil when the tap already delivers 48kHz mono.
    private var converter: AVAudioConverter?
    private var monoFormat: AVAudioFormat?

    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let _isPaused = OSAllocatedUnfairLock(initialState: false)
    private let _firstBufferAt = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private let _writeFailed = OSAllocatedUnfairLock(initialState: false)

    /// Start capturing system audio into `url` (use a .caf extension).
    func start(writingTo url: URL) throws {
        guard _isCapturing.withLock({ !$0 }) else { return }
        _firstBufferAt.withLock { $0 = nil }
        _writeFailed.withLock { $0 = false }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "EchoNotes system tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw CaptureError.tapCreationFailed(status) }
        tapID = newTapID

        do {
            let format = try readTapFormat()
            try createAggregateDevice(tapUUID: description.uuid)
            file = try Self.makeFile(url: url, format: format)
            try setUpMonoFeed(from: format)
            try installIOProc(format: format)
        } catch {
            teardown()
            throw error
        }

        _isCapturing.withLock { $0 = true }
        logger.info("System tap capture started → \(url.lastPathComponent)")
    }

    /// Stop the IO proc but keep the tap, device, and open file — resumable.
    func pauseCapture() {
        guard _isCapturing.withLock({ $0 }), _isPaused.withLock({ !$0 }) else { return }
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        _isPaused.withLock { $0 = true }
    }

    /// Restart the IO proc after a pause.
    func resumeCapture() throws {
        guard _isCapturing.withLock({ $0 }), _isPaused.withLock({ $0 }) else { return }
        guard let procID, aggregateID != kAudioObjectUnknown else { return }
        let status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw CaptureError.deviceStartFailed(status) }
        _isPaused.withLock { $0 = false }
    }

    /// Stop capturing, tear down the tap, and close the file. Idempotent.
    func stopCapture() {
        guard _isCapturing.withLock({ $0 }) else { return }
        _isCapturing.withLock { $0 = false }
        _isPaused.withLock { $0 = false }
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        teardown()
    }

    // MARK: - Setup

    private func readTapFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw CaptureError.tapFormatUnreadable(status)
        }
        return format
    }

    private func createAggregateDevice(tapUUID: UUID) throws {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EchoNotes-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggregateID)
        guard status == noErr else { throw CaptureError.aggregateCreationFailed(status) }
        aggregateID = newAggregateID
    }

    private static func makeFile(url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            throw CaptureError.fileCreationFailed(error)
        }
    }

    /// Prepare the 48kHz mono conversion used for level meters and live
    /// transcription. The file itself is written in the tap's native format.
    private func setUpMonoFeed(from tapFormat: AVAudioFormat) throws {
        guard let mono = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioConfig.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.formatCreationFailed
        }
        monoFormat = mono

        if tapFormat.sampleRate == mono.sampleRate,
           tapFormat.channelCount == 1,
           tapFormat.commonFormat == .pcmFormatFloat32 {
            converter = nil
            return
        }
        guard let conv = AVAudioConverter(from: tapFormat, to: mono) else {
            throw CaptureError.formatCreationFailed
        }
        converter = conv
    }

    private func installIOProc(format: AVAudioFormat) throws {
        var newProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&newProcID, aggregateID, queue) {
            [weak self] _, inInputData, _, _, _ in
            self?.handleInput(inInputData, format: format)
        }
        guard status == noErr, let newProcID else {
            throw CaptureError.ioProcCreationFailed(status)
        }
        procID = newProcID

        let startStatus = AudioDeviceStart(aggregateID, newProcID)
        guard startStatus == noErr else { throw CaptureError.deviceStartFailed(startStatus) }
    }

    // MARK: - Capture path (runs on `queue`)

    private func handleInput(_ inputData: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        guard let file, !_writeFailed.withLock({ $0 }) else { return }
        _firstBufferAt.withLock { if $0 == nil { $0 = Date() } }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            bufferListNoCopy: inputData,
            deallocator: nil
        ) else { return }

        do {
            try file.write(from: buffer)
        } catch {
            reportWriteFailure(error)
            return
        }

        guard onBuffer != nil, let samples = monoSamples(from: buffer) else { return }
        onBuffer?(SourcedAudioBuffer(samples: samples, source: .system))
    }

    private func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let converter, let monoFormat else {
            // Tap already delivers 48kHz mono float.
            guard let data = buffer.floatChannelData else { return nil }
            return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }

        let ratio = monoFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: capacity) else {
            return nil
        }

        let didProvideInput = OSAllocatedUnfairLock(initialState: false)
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            let shouldProvideInput = didProvideInput.withLock { provided in
                guard !provided else { return false }
                provided = true
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
            logger.error("System audio downmix failed: \(error.localizedDescription)")
            return nil
        }
        guard let data = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    private func reportWriteFailure(_ error: Error) {
        let firstFailure = _writeFailed.withLock { failed -> Bool in
            guard !failed else { return false }
            failed = true
            return true
        }
        guard firstFailure else { return }
        logger.error("System track write failed: \(error.localizedDescription)")
        onError?(error)
    }

    // MARK: - Teardown

    private func teardown() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        // Serialize with any in-flight IO block before closing the file.
        queue.sync {
            self.file = nil
            self.converter = nil
            self.monoFormat = nil
        }
    }
}
