import Foundation
import WhisperKit

/// Wraps WhisperKit for on-device speech-to-text.
/// Handles both file-based and direct sample transcription.
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
        let result = try await whisperKit.transcribe(audioPath: audioURL.path)

        progressCallback?(1.0)

        return result.flatMap { $0.segments.map { segment in
            TranscriptSegment(
                startTime: Double(segment.start),
                endTime: Double(segment.end),
                text: segment.text
            )
        }}
    }

    /// Transcribe raw 16kHz mono Float32 PCM samples.
    func transcribeSamples(_ samples: [Float]) async throws -> [TranscriptSegment] {
        let result = try await whisperKit.transcribe(audioArray: samples)

        return result.flatMap { $0.segments.map { segment in
            TranscriptSegment(
                startTime: Double(segment.start),
                endTime: Double(segment.end),
                text: segment.text
            )
        }}
    }
}

enum WhisperError: LocalizedError {
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .audioConversionFailed: return "Failed to convert audio format."
        }
    }
}
