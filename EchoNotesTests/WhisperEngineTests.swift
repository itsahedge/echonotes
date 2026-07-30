import Testing
import AVFoundation
@testable import EchoNotes

@Suite("WhisperEngine audio loading")
struct WhisperEngineTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    /// Write a PCM CAF with `seconds` of a 440Hz sine at `sampleRate`/`channels`.
    private func makeCAF(seconds: Double, sampleRate: Double, channels: UInt32) throws -> URL {
        let url = tempDir.appendingPathComponent("test-\(sampleRate)-\(channels).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false
        ))
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            guard let data = buffer.floatChannelData?[channel] else { continue }
            for i in 0..<Int(frames) {
                data[i] = sin(Float(i) * 2 * .pi * 440 / Float(sampleRate)) * 0.5
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test("48kHz stereo resamples and downmixes to 16kHz mono")
    func stereo48kTo16kMono() throws {
        let url = try makeCAF(seconds: 1.0, sampleRate: 48000, channels: 2)
        let samples = try WhisperEngine.loadMono16k(url: url)

        // ~1 second of 16kHz audio, allowing for resampler edge effects.
        #expect(abs(samples.count - 16000) < 200)
        #expect(samples.contains { abs($0) > WhisperEngine.silenceThreshold })
    }

    @Test("16kHz mono loads without conversion")
    func mono16kPassthrough() throws {
        let url = try makeCAF(seconds: 0.5, sampleRate: 16000, channels: 1)
        let samples = try WhisperEngine.loadMono16k(url: url)
        #expect(samples.count == 8000)
    }

    @Test("Zero-frame file yields no samples instead of crashing")
    func emptyFile() throws {
        let url = tempDir.appendingPathComponent("empty.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
        ]
        // Create and immediately close a file with no frames written.
        _ = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let samples = try WhisperEngine.loadMono16k(url: url)
        #expect(samples.isEmpty)
    }
}
