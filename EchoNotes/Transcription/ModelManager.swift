import Foundation

/// Supported Whisper model sizes with download URLs and expected file sizes.
enum WhisperModel: String, CaseIterable, Sendable {
    case tinyEn = "ggml-tiny.en"
    case baseEn = "ggml-base.en"
    case smallEn = "ggml-small.en"
    case mediumEn = "ggml-medium.en"

    var filename: String { "\(rawValue).bin" }

    var displayName: String {
        switch self {
        case .tinyEn: return "Tiny (English)"
        case .baseEn: return "Base (English)"
        case .smallEn: return "Small (English)"
        case .mediumEn: return "Medium (English)"
        }
    }

    /// Approximate download size in MB for display.
    var approximateSizeMB: Int {
        switch self {
        case .tinyEn: return 75
        case .baseEn: return 150
        case .smallEn: return 500
        case .mediumEn: return 1500
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}

/// Manages Whisper model files — checks existence and downloads from Hugging Face.
@MainActor
final class ModelManager: ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    /// Directory where models are stored.
    nonisolated static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("EchoNotes/Models", isDirectory: true)
    }

    /// Full path for a given model.
    nonisolated static func modelPath(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.filename)
    }

    /// Check if a model file exists on disk.
    nonisolated static func modelExists(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }

    /// Ensure a model is available, downloading if necessary. Returns the file URL.
    func ensureModel(_ model: WhisperModel) async throws -> URL {
        let path = Self.modelPath(for: model)
        if Self.modelExists(model) {
            return path
        }
        return try await downloadModel(model)
    }

    /// Download a model from Hugging Face with progress reporting.
    @discardableResult
    func downloadModel(_ model: WhisperModel) async throws -> URL {
        let destination = Self.modelPath(for: model)

        // Ensure directory exists
        try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)

        isDownloading = true
        downloadProgress = 0
        error = nil

        defer {
            isDownloading = false
        }

        do {
            let url = try await performDownload(from: model.downloadURL, to: destination)
            return url
        } catch {
            self.error = "Download failed: \(error.localizedDescription)"
            throw error
        }
    }

    private func performDownload(from remoteURL: URL, to destination: URL) async throws -> URL {
        let tempURL = destination.appendingPathExtension("download")

        // Use URLSession download task with delegate for efficient streaming
        let delegate = DownloadDelegate { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
            }
        }

        let (downloadedURL, response) = try await URLSession.shared.download(from: remoteURL, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }

        // Move from system temp to our temp location, then atomic move to final
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: tempURL)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        await MainActor.run { self.downloadProgress = 1.0 }
        return destination
    }
}

/// Reports download progress via URLSessionDownloadDelegate.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download call
    }
}

enum ModelError: LocalizedError {
    case downloadFailed
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Failed to download model from Hugging Face."
        case .modelNotFound: return "Whisper model file not found."
        }
    }
}
