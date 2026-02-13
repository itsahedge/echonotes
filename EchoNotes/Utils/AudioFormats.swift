import AVFoundation

/// Audio format utilities.
enum AudioFormats {
    /// Calculate RMS level for visualization.
    static func rmsLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }
}
