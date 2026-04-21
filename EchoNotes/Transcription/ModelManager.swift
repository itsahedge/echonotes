import Foundation
import WhisperKit
import os

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
@Observable
final class ModelManager {
    @ObservationIgnored private let logger = Logger(subsystem: "com.echonotes", category: "ModelManager")
    var isDownloading = false
    var isLoading = false
    var downloadProgress: Double = 0
    var error: String?

    @ObservationIgnored private var whisperKit: WhisperKit?
    @ObservationIgnored private var loadedModel: WhisperModel?
    @ObservationIgnored private var progressMonitorTask: Task<Void, Never>?

    /// Get a ready-to-use WhisperEngine, downloading the model if needed.
    func ensureEngine(for model: WhisperModel) async throws -> WhisperEngine {
        if let whisperKit, loadedModel == model {
            return WhisperEngine(whisperKit: whisperKit)
        }

        error = nil
        let needsDownload = !Self.modelLikelyCached()
        
        if needsDownload {
            isDownloading = true
            downloadProgress = 0
            monitorDownloadProgress(for: model)
        } else {
            isLoading = true
        }

        defer { 
            isDownloading = false
            isLoading = false
            progressMonitorTask?.cancel()
            progressMonitorTask = nil
        }

        do {
            logger.info("Initializing WhisperKit with model: \(model.rawValue) (cached: \(!needsDownload))")
            let config = WhisperKitConfig(model: model.rawValue)
            let kit = try await WhisperKit(config)
            logger.info("WhisperKit initialized successfully")
            self.whisperKit = kit
            self.loadedModel = model
            self.downloadProgress = 1.0
            return WhisperEngine(whisperKit: kit)
        } catch {
            logger.error("WhisperKit failed: \(error.localizedDescription)")
            self.error = "Model error: \(error.localizedDescription)"
            throw error
        }
    }

    /// Check if WhisperKit models are likely cached.
    /// WhisperKit's Hub library stores models in ~/Documents/huggingface/models/
    nonisolated static func modelLikelyCached() -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    /// Monitor download progress by polling the model directory size.
    /// WhisperKit's Hub library downloads to ~/Documents/huggingface/models/
    private func monitorDownloadProgress(for model: WhisperModel) {
        let expectedBytes = Int64(model.approximateSizeMB) * 1024 * 1024
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        
        progressMonitorTask = Task {
            while !Task.isCancelled {
                // Run disk I/O on background thread
                let currentSize = await Task.detached {
                    self.directorySize(at: modelDir)
                }.value
                
                let progress = min(0.99, Double(currentSize) / Double(expectedBytes))
                
                // Only hop to MainActor to update @Published property
                await MainActor.run {
                    self.downloadProgress = progress
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
        }
    }

    /// Calculate total size of a directory and its contents.
    private nonisolated func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else { continue }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }
}
