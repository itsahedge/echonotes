import Foundation
import WhisperKit

/// Supported Whisper model sizes.
enum WhisperModel: String, CaseIterable, Sendable {
    case tiny = "tiny.en"
    case base = "base.en"
    case small = "small.en"
    case medium = "medium.en"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (English)"
        case .base: return "Base (English)"
        case .small: return "Small (English)"
        case .medium: return "Medium (English)"
        }
    }

    var approximateSizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 150
        case .small: return 500
        case .medium: return 1500
        }
    }
}

/// Manages WhisperKit initialization and model loading.
/// WhisperKit handles model downloads and caching internally.
@MainActor
final class ModelManager: ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    private var whisperKit: WhisperKit?
    private var loadedModel: WhisperModel?

    /// Get a ready-to-use WhisperEngine, downloading the model if needed.
    func ensureEngine(for model: WhisperModel) async throws -> WhisperEngine {
        if let whisperKit, loadedModel == model {
            return WhisperEngine(whisperKit: whisperKit)
        }

        isDownloading = true
        downloadProgress = 0
        error = nil

        defer { isDownloading = false }

        do {
            let config = WhisperKitConfig(model: model.rawValue)
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.loadedModel = model
            self.downloadProgress = 1.0
            return WhisperEngine(whisperKit: kit)
        } catch {
            self.error = "Failed to load model: \(error.localizedDescription)"
            throw error
        }
    }

    /// Check if WhisperKit models are likely cached.
    /// Best-effort — WhisperKit manages its own cache; we just check if the directory exists.
    nonisolated static func modelLikelyCached() -> Bool {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelDir = cacheDir.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        return FileManager.default.fileExists(atPath: modelDir.path)
    }
}
