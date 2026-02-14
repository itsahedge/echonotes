import Testing
@testable import EchoNotes

@Suite("AudioConfig Constants")
struct ConstantsTests {
    @Test("Sample rate is 48000Hz")
    func sampleRate() {
        #expect(AudioConfig.sampleRate == 48000)
    }
    
    @Test("Sample rate is a positive value")
    func sampleRatePositive() {
        #expect(AudioConfig.sampleRate > 0)
    }
}
