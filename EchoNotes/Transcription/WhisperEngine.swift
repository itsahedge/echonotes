import Foundation
import WhisperKit

/// Wraps WhisperKit for on-device speech-to-text.
final class WhisperEngine: @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// Transcribe an audio file (M4A, WAV, etc).
    func transcribe(
        audioURL: URL,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        let result = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            callback: { progress in
                // Approximate progress from window position vs total audio
                let audioSeconds = progress.timings.inputAudioSeconds
                if audioSeconds > 0 {
                    let processed = Double(progress.windowId + 1) * 30.0
                    progressCallback?(min(processed / audioSeconds, 0.99))
                }
                return nil // continue transcription
            }
        )

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
