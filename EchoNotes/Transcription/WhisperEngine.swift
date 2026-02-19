import Foundation
import WhisperKit
@preconcurrency import AVFoundation
import os

/// Wraps WhisperKit for on-device speech-to-text.
final class WhisperEngine: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.echonotes", category: "WhisperEngine")
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// Transcribe an audio file (M4A, WAV, etc).
    func transcribe(
        audioURL: URL,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        logger.info("Starting transcription of \(audioURL.lastPathComponent)")
        let result = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            callback: { [logger] progress in
                let audioSeconds = progress.timings.inputAudioSeconds
                logger.debug("Window \(progress.windowId), audio: \(audioSeconds)s")
                if audioSeconds > 0 {
                    let processed = Double(progress.windowId + 1) * 30.0
                    progressCallback?(min(processed / audioSeconds, 0.99))
                }
                return nil // continue transcription
            }
        )

        let totalSegments = result.flatMap { $0.segments }.count
        logger.info("Transcription complete: \(result.count) results, \(totalSegments) segments")
        
        progressCallback?(1.0)
        return mapResults(result)
    }

    /// Transcribe raw 16kHz mono Float32 PCM samples.
    func transcribeSamples(_ samples: [Float], speaker: String? = nil) async throws -> [TranscriptSegment] {
        let result = try await whisperKit.transcribe(audioArray: samples)
        return mapResults(result, speaker: speaker)
    }

    /// Minimum RMS amplitude to consider a channel non-silent.
    /// Below this threshold, the channel is treated as empty (no speech).
    static let silenceThreshold: Float = 0.001

    /// Transcribe a stereo file with speaker diarization.
    /// Left channel = system audio (remote), right channel = mic (user).
    /// Falls back to non-diarized transcription for mono files.
    func transcribeDiarized(
        audioURL: URL,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        logger.info("Starting diarized transcription of \(audioURL.lastPathComponent)")

        // Fall back to standard transcription for mono files
        guard Self.isStereo(url: audioURL) else {
            logger.info("Mono file detected — falling back to non-diarized transcription")
            return try await transcribe(audioURL: audioURL, progressCallback: progressCallback)
        }

        let (systemSamples, micSamples) = try Self.splitChannels(url: audioURL)
        logger.info("Split channels: system=\(systemSamples.count) mic=\(micSamples.count) samples")

        // Transcribe system audio (left channel = remote speaker) — 0-50% progress
        let systemSegments: [TranscriptSegment]
        if systemSamples.contains(where: { abs($0) > Self.silenceThreshold }) {
            systemSegments = try await transcribeSamples(systemSamples, speaker: Speaker.remote.rawValue)
        } else {
            systemSegments = []
        }
        progressCallback?(0.5)

        // Transcribe mic audio (right channel = user) — 50-100% progress
        let micSegments: [TranscriptSegment]
        if micSamples.contains(where: { abs($0) > Self.silenceThreshold }) {
            micSegments = try await transcribeSamples(micSamples, speaker: Speaker.user.rawValue)
        } else {
            micSegments = []
        }
        progressCallback?(1.0)

        // Merge chronologically
        let merged = (systemSegments + micSegments).sorted { $0.startTime < $1.startTime }
        logger.info("Diarized transcription complete: \(merged.count) segments")
        return merged
    }

    /// Check if an audio file has 2+ channels without reading the full file.
    nonisolated static func isStereo(url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.processingFormat.channelCount >= 2
    }

    /// Split a stereo audio file into two mono Float32 arrays at 16kHz.
    /// Returns (leftChannel, rightChannel).
    nonisolated static func splitChannels(url: URL) throws -> ([Float], [Float]) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "com.echonotes.whisper", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }
        try file.read(into: buffer)

        let channelCount = Int(format.channelCount)
        guard channelCount >= 2, let channelData = buffer.floatChannelData else {
            throw NSError(domain: "com.echonotes.whisper", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Audio file is not stereo"])
        }

        let count = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        let right = Array(UnsafeBufferPointer(start: channelData[1], count: count))

        // Resample to 16kHz if needed
        let srcRate = format.sampleRate
        if abs(srcRate - 16000) < 1 {
            return (left, right)
        }

        let leftResampled = try resampleMono(left, from: srcRate, to: 16000)
        let rightResampled = try resampleMono(right, from: srcRate, to: 16000)
        return (leftResampled, rightResampled)
    }

    /// Resample mono Float32 samples between sample rates.
    nonisolated private static func resampleMono(_ samples: [Float], from srcRate: Double, to dstRate: Double) throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        let srcFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: srcRate, channels: 1, interleaved: false)!
        let dstFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: dstRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: srcFmt, to: dstFmt) else {
            throw NSError(domain: "com.echonotes.whisper", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create resampler"])
        }

        let inBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(samples.count))!
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            inBuf.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }

        let outFrames = AVAudioFrameCount(Double(samples.count) * dstRate / srcRate) + 256
        let outBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: outFrames)!

        var fed = false
        var err: NSError?
        converter.convert(to: outBuf, error: &err) { _, status in
            if !fed { fed = true; status.pointee = .haveData; return inBuf }
            status.pointee = .noDataNow; return nil
        }
        if let err { throw err }

        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
    }

    private func mapResults(_ results: [TranscriptionResult], speaker: String? = nil) -> [TranscriptSegment] {
        results.flatMap { $0.segments.map { segment in
            TranscriptSegment(
                startTime: Double(segment.start),
                endTime: Double(segment.end),
                text: segment.text,
                speaker: speaker
            )
        }}
    }
}
