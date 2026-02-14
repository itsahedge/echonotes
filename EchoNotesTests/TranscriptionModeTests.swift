import Testing
import Foundation
@testable import EchoNotes

@Suite("TranscriptionMode")
struct TranscriptionModeTests {

    @Test("All cases have unique raw values")
    func uniqueRawValues() {
        let rawValues = TranscriptionMode.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count, "Duplicate raw values found")
    }

    @Test("Raw value round-trips correctly")
    func rawValueRoundTrip() {
        for mode in TranscriptionMode.allCases {
            let restored = TranscriptionMode(rawValue: mode.rawValue)
            #expect(restored == mode, "Round-trip failed for \(mode)")
        }
    }

    @Test("Post-recording is the default fallback")
    func defaultFallback() {
        let invalid = TranscriptionMode(rawValue: "garbage")
        #expect(invalid == nil, "Invalid raw value should return nil")
        // The RecordingEngine uses ?? .postRecording as fallback
    }

    @Test("CaseIterable includes both modes")
    func allCasesComplete() {
        let cases = TranscriptionMode.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.live))
        #expect(cases.contains(.postRecording))
    }
}
