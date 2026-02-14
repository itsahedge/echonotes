import Testing
@testable import EchoNotes

@Suite("SourcedAudioBuffer RMS")
struct AudioFormatsTests {
    @Test("Silence produces zero RMS")
    func silenceRms() {
        let silence = [Float](repeating: 0, count: 1000)
        #expect(SourcedAudioBuffer.rmsLevel(silence) == 0)
    }

    @Test("Constant signal RMS equals its value")
    func constantSignal() {
        let signal = [Float](repeating: 0.5, count: 1000)
        let rms = SourcedAudioBuffer.rmsLevel(signal)
        #expect(abs(rms - 0.5) < 0.001)
    }

    @Test("Full-scale signal produces RMS of 1.0")
    func fullScale() {
        let signal = [Float](repeating: 1.0, count: 100)
        let rms = SourcedAudioBuffer.rmsLevel(signal)
        #expect(abs(rms - 1.0) < 0.001)
    }

    @Test("Alternating +1/-1 produces RMS of 1.0")
    func alternatingSignal() {
        let signal = (0..<1000).map { Float($0 % 2 == 0 ? 1.0 : -1.0) }
        let rms = SourcedAudioBuffer.rmsLevel(signal)
        #expect(abs(rms - 1.0) < 0.001)
    }

    @Test("Empty array returns zero")
    func emptyArray() {
        #expect(SourcedAudioBuffer.rmsLevel([]) == 0)
    }
}
