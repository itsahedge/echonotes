import ScreenCaptureKit
import AVFoundation
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

    private var stream: SCStream?
    private let _isCapturing = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.echonotes", category: "SystemAudioCapture")

    /// Start capturing system audio at the given sample rate (mono Float32).
    func startCapture(sampleRate: Double = AudioConfig.sampleRate) async throws {
        guard _isCapturing.withLock({ !$0 }) else { return }

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
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        self.stream = stream
        _isCapturing.withLock { $0 = true }
    }

    func stopCapture() async {
        guard _isCapturing.withLock({ $0 }), let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        _isCapturing.withLock { $0 = false }
    }
}

extension SystemAudioCapture: SCStreamOutput {
    /// Receives audio sample buffers from ScreenCaptureKit.
    /// We only registered for .audio type, so no video data is processed here.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio buffers (we only registered for .audio type)
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let dataBuffer = sampleBuffer.dataBuffer else { return }

        let length = dataBuffer.dataLength

        do {
            var rawData = Data(count: length)
            try rawData.withUnsafeMutableBytes { ptr in
                try dataBuffer.copyDataBytes(to: ptr)
            }
            let floatCount = length / MemoryLayout<Float>.size
            let samples = rawData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self).prefix(floatCount))
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
