import Testing
import CoreMedia
@testable import EchoNotes

@Suite("TimestampedBuffer")
struct TimestampedBufferTests {
    @Test("System buffer stores samples and source")
    func systemBuffer() {
        let samples: [Float] = [0.1, 0.2, 0.3]
        let ts = CMTime(value: 48000, timescale: 48000)
        let buffer = TimestampedBuffer(samples: samples, timestamp: ts, source: .system)

        #expect(buffer.samples.count == 3)
        #expect(buffer.source == .system)
        #expect(abs(buffer.timestamp.seconds - 1.0) < 0.001)
    }

    @Test("Mic buffer stores samples and source")
    func micBuffer() {
        let samples: [Float] = [0.5, -0.5]
        let ts = CMTime(value: 0, timescale: 48000)
        let buffer = TimestampedBuffer(samples: samples, timestamp: ts, source: .microphone)

        #expect(buffer.samples.count == 2)
        #expect(buffer.source == .microphone)
    }
}
