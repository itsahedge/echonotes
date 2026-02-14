import Testing
@testable import EchoNotes

@Suite("SourcedAudioBuffer")
struct SourcedAudioBufferTests {
    @Test("System buffer stores samples and source")
    func systemBuffer() {
        let samples: [Float] = [0.1, 0.2, 0.3]
        let buffer = SourcedAudioBuffer(samples: samples, source: .system)

        #expect(buffer.samples.count == 3)
        #expect(buffer.source == .system)
    }

    @Test("Mic buffer stores samples and source")
    func micBuffer() {
        let samples: [Float] = [0.5, -0.5]
        let buffer = SourcedAudioBuffer(samples: samples, source: .microphone)

        #expect(buffer.samples.count == 2)
        #expect(buffer.source == .microphone)
    }
}
