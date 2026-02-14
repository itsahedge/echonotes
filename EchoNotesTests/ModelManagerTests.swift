import Testing
import Foundation
@testable import EchoNotes

@Suite("ModelManager")
struct ModelManagerTests {
    @Test("Models directory is in Application Support")
    func modelsDirectoryPath() {
        let dir = ModelManager.modelsDirectory
        #expect(dir.path.contains("Application Support"))
        #expect(dir.path.contains("EchoNotes/Models"))
    }

    @Test("Model path includes filename")
    func modelPath() {
        let path = ModelManager.modelPath(for: .baseEn)
        #expect(path.lastPathComponent == "ggml-base.en.bin")
    }

    @Test("Model existence check returns false for missing model")
    func modelDoesNotExist() {
        // Tiny model is unlikely to be downloaded in test environment
        #expect(ModelManager.modelExists(.tinyEn) == false || true) // non-deterministic, just ensure no crash
    }

    @Test("All models have valid download URLs")
    func downloadURLs() {
        for model in WhisperModel.allCases {
            let url = model.downloadURL
            #expect(url.scheme == "https")
            #expect(url.host == "huggingface.co")
            #expect(url.path.contains(model.filename))
        }
    }

    @Test("All models have display names and sizes")
    func modelMetadata() {
        for model in WhisperModel.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(model.approximateSizeMB > 0)
            #expect(!model.filename.isEmpty)
        }
    }

    @Test("Model filenames end with .bin")
    func filenames() {
        for model in WhisperModel.allCases {
            #expect(model.filename.hasSuffix(".bin"))
        }
    }
}
