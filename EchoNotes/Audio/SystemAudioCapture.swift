import ScreenCaptureKit
import AVFoundation
import AppKit
import CoreMedia
import os

/// Captures system-wide audio output using ScreenCaptureKit's audio API.
///
/// **AUDIO-ONLY MODE** — No video, screen, or visual data is captured.
///
/// This captures what the user hears (system audio output):
/// - Other people on calls (Zoom, Meet, FaceTime, Discord, etc.)
/// - Any audio playing through the system
///
/// Requires "Screen & System Audio Recording" permission (macOS requirement for audio API access).
final class SystemAudioCapture: NSObject, @unchecked Sendable {
    var onBuffer: ((SourcedAudioBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    
    static func availableDevices() -> [String] {
        // Return empty array - system audio doesn't have selectable devices on macOS
        return []
    }

    private var stream: SCStream?
    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let _pendingResume = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.echonotes", category: "SystemAudioCapture")
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var capturedSampleRate: Double = AudioConfig.sampleRate

    /// Start capturing system audio at the given sample rate (mono Float32).
    func startCapture(sampleRate: Double = AudioConfig.sampleRate) async throws {
        guard _isCapturing.withLock({ !$0 }) else { return }
        capturedSampleRate = sampleRate
        installSleepWakeObservers()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        // Audio-only configuration
        config.capturesAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true

        // Set minimal video config (we only register for .audio output, so no video data is processed)
        // ScreenCaptureKit requires a video configuration even for audio-only capture.
        // We use the smallest possible dimensions (2x2) to minimize overhead.
        // If 2x2 fails on some systems, we fallback to 16x16.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        
        // Try to start with 2x2, fallback to 16x16 if it fails
        do {
            try await stream.startCapture()
            self.stream = stream
        } catch {
            logger.warning("Failed to start capture with 2x2 config, retrying with 16x16: \(error.localizedDescription)")
            config.width = 16
            config.height = 16
            
            // Clean up the original stream before creating a new one to avoid leaking the delegate reference
            try? stream.removeStreamOutput(self, type: .audio)
            
            // Create a NEW stream with updated config (old stream may be in bad state)
            let fallbackStream = SCStream(filter: filter, configuration: config, delegate: self)
            try fallbackStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await fallbackStream.startCapture()
            self.stream = fallbackStream
        }

        _isCapturing.withLock { $0 = true }
    }

    func stopCapture() async {
        guard _isCapturing.withLock({ $0 }) else { return }
        removeSleepWakeObservers()
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        _isCapturing.withLock { $0 = false }
        _pendingResume.withLock { $0 = false }
    }

    // MARK: - Sleep/Wake Handling

    /// Tear down the SCStream before sleep to prevent stale XPC connections.
    /// On wake, re-create the stream if we were capturing.
    private func installSleepWakeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter

        sleepObserver = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let wasCapturing = self._isCapturing.withLock { $0 }
            guard wasCapturing else { return }
            self.logger.info("System going to sleep — tearing down SCStream to prevent stale state")
            self._pendingResume.withLock { $0 = true }
            // Synchronously nil out the stream to prevent delegate callbacks on a dead XPC connection
            if let stream = self.stream {
                try? stream.removeStreamOutput(self, type: .audio)
            }
            self.stream = nil
        }

        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self._pendingResume.withLock({ $0 }) else { return }
            self.logger.info("System woke up — re-creating SCStream")
            self._pendingResume.withLock { $0 = false }
            Task {
                // Brief delay to let ScreenCaptureKit daemon stabilize after wake
                try? await Task.sleep(for: .seconds(1))
                do {
                    // Temporarily mark as not capturing so startCapture guard passes
                    self._isCapturing.withLock { $0 = false }
                    try await self.startCapture(sampleRate: self.capturedSampleRate)
                } catch {
                    self.logger.error("Failed to resume system audio after wake: \(error.localizedDescription)")
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
}

extension SystemAudioCapture: SCStreamOutput {
    /// Receives audio sample buffers from ScreenCaptureKit.
    /// We only registered for .audio type, so no video data is processed here.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio buffers (we only registered for .audio type)
        guard type == .audio, sampleBuffer.isValid else { return }
        // Guard against callbacks from a stream we've already torn down (e.g. post-sleep)
        guard self.stream === stream else { return }
        guard let dataBuffer = sampleBuffer.dataBuffer else { return }

        let length = dataBuffer.dataLength
        let floatCount = length / MemoryLayout<Float>.size

        do {
            // Single-copy approach: access buffer bytes directly without intermediate Data allocation
            let samples = try dataBuffer.withContiguousStorage { ptr in
                Array(UnsafeBufferPointer(start: ptr.baseAddress?.assumingMemoryBound(to: Float.self),
                                          count: floatCount))
            }
            onBuffer?(SourcedAudioBuffer(samples: samples, source: .system))
        } catch {
            logger.error("Error extracting system audio: \(error.localizedDescription)")
        }
    }
}

extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("System audio stream stopped with error: \(error.localizedDescription)")
        // Guard against delegate calls on a stream we've already torn down
        guard self.stream === stream else {
            logger.info("Ignoring didStopWithError for a detached stream (likely post-sleep cleanup)")
            return
        }
        self.stream = nil
        _isCapturing.withLock { $0 = false }
        onError?(error)
    }
}

enum CaptureError: LocalizedError {
    case noDisplayFound
    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No display found for audio capture."
        }
    }
}
