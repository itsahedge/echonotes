import Foundation
import WhisperKit
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
    func transcribeSamples(_ samples: [Float]) async throws -> [TranscriptSegment] {
        let result = try await whisperKit.transcribe(audioArray: samples)
        return mapResults(result)
    }

    private func mapResults(_ results: [TranscriptionResult]) -> [TranscriptSegment] {
        results.flatMap { $0.segments.map { segment in
            TranscriptSegment(
                startTime: Double(segment.start),
                endTime: Double(segment.end),
                text: segment.text
            )
        }}
    }
}
