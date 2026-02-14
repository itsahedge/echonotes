import Testing
import Foundation
@testable import EchoNotes

@Suite("ModelManager")
struct ModelManagerTests {
    @Test("All models have display names and sizes")
    func modelMetadata() {
        for model in WhisperModel.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(model.approximateSizeMB > 0)
        }
    }

    @Test("All models have unique raw values")
    func uniqueRawValues() {
        let rawValues = WhisperModel.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("Model existence check doesn't crash")
    func modelExistsCheck() {
        // Just ensure it doesn't crash — result is non-deterministic
        _ = ModelManager.modelExists(.tiny)
    }
}
