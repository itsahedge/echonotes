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
            
            // Start progress monitoring task
            // WhisperKit doesn't expose download progress callbacks, so we poll the cache directory size
            let progressTask = Task {
                await monitorDownloadProgress(for: model)
            }
            
            let kit = try await WhisperKit(config)
            
            // Cancel progress monitoring once download completes
            progressTask.cancel()
            
            self.whisperKit = kit
            self.loadedModel = model
            self.downloadProgress = 1.0
            return WhisperEngine(whisperKit: kit)
        } catch {
            self.error = "Failed to load model: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Monitor cache directory size to estimate download progress.
    /// This is a workaround since WhisperKit doesn't expose progress callbacks.
    private func monitorDownloadProgress(for model: WhisperModel) async {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelDir = cacheDir.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        let expectedSizeMB = model.approximateSizeMB
        let expectedBytes = Int64(expectedSizeMB) * 1_024 * 1_024
        
        while !Task.isCancelled {
            do {
                // Get total size of cache directory
                let currentSize = try directorySize(at: modelDir)
                let progress = min(Double(currentSize) / Double(expectedBytes), 0.99) // Cap at 99% until WhisperKit completes
                
                await MainActor.run {
                    self.downloadProgress = progress
                }
                
                // Poll every 500ms
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                // Directory doesn't exist yet or other error - keep waiting
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    
    /// Calculate total size of a directory recursively.
    private func directorySize(at url: URL) throws -> Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }

    /// Check if WhisperKit models are likely cached.
    /// Best-effort — WhisperKit manages its own cache; we just check if the directory exists.
    nonisolated static func modelLikelyCached() -> Bool {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelDir = cacheDir.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        return FileManager.default.fileExists(atPath: modelDir.path)
    }
}
