import Testing
import Foundation
@testable import EchoNotes

@Suite("StreamingTranscriber")
struct StreamingTranscriberTests {

    @Test("Reset clears all state")
    @MainActor func resetClearsState() async {
        let transcriber = StreamingTranscriber()
        transcriber.feedSamples(Array(repeating: Float(0.5), count: 1000))
        try? await Task.sleep(nanoseconds: 50_000_000)

        transcriber.reset()

        #expect(transcriber.segments.isEmpty)
        #expect(!transcriber.isProcessing)
        #expect(transcriber.error == nil)
    }

    @Test("Samples below threshold don't trigger processing")
    @MainActor func belowThresholdNoProcessing() async {
        let transcriber = StreamingTranscriber()

        // Feed less than 5s of audio at 48kHz (5 * 48000 = 240,000)
        transcriber.feedSamples(Array(repeating: Float(0.1), count: 1000))
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(!transcriber.isProcessing)
        #expect(transcriber.segments.isEmpty)
    }

    @Test("Flush with no samples is a no-op")
    @MainActor func flushEmpty() async {
        let transcriber = StreamingTranscriber()
        await transcriber.flush()
        #expect(transcriber.segments.isEmpty)
    }

    @Test("Reset cancels any pending work")
    @MainActor func resetCancelsPending() async {
        let transcriber = StreamingTranscriber()
        transcriber.feedSamples(Array(repeating: Float(0.1), count: 50000))
        try? await Task.sleep(nanoseconds: 50_000_000)

        transcriber.reset()

        #expect(transcriber.segments.isEmpty)
        #expect(!transcriber.isProcessing)
    }
}

@Suite("TranscriptionMode")
struct TranscriptionModeTests {

    @Test("All cases have unique raw values")
    func uniqueRawValues() {
        let rawValues = TranscriptionMode.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("Raw value round-trips correctly")
    func rawValueRoundTrip() {
        for mode in TranscriptionMode.allCases {
            #expect(TranscriptionMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("Invalid raw value returns nil")
    func invalidRawValue() {
        #expect(TranscriptionMode(rawValue: "garbage") == nil)
    }

    @Test("Both modes exist")
    func allCases() {
        let cases = TranscriptionMode.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.live))
        #expect(cases.contains(.postRecording))
    }
}
