import AVFoundation
import CoreMedia

/// A timestamped audio buffer from either system audio or microphone.
struct TimestampedBuffer: Sendable {
    let samples: [Float]
    let timestamp: CMTime
    let source: AudioSource

    enum AudioSource: Sendable {
        case system
        case microphone
    }
}
