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
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }

        let totalBytes = response.expectedContentLength
        var data = Data()
        if totalBytes > 0 {
            data.reserveCapacity(Int(totalBytes))
        }

        var downloadedBytes: Int64 = 0
        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1
            if totalBytes > 0 && downloadedBytes % 65536 == 0 {
                let progress = Double(downloadedBytes) / Double(totalBytes)
                await MainActor.run { self.downloadProgress = progress }
            }
        }

        await MainActor.run { self.downloadProgress = 1.0 }
        try data.write(to: destination, options: .atomic)
        return destination
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
