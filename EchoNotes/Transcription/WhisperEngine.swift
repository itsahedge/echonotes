import Foundation
@preconcurrency import AVFoundation
import CWhisper

/// Wraps the whisper.cpp C API to perform speech-to-text on audio files.
/// All inference runs off the main thread to keep the UI responsive.
final class WhisperEngine: @unchecked Sendable {
    private var context: OpaquePointer?

    /// Load a Whisper GGML model from disk.
    init(modelPath: URL) throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw WhisperError.modelNotFound
        }
        guard let ctx = whisper_init_from_file(modelPath.path) else {
            throw WhisperError.modelLoadFailed
        }
        self.context = ctx
    }

    deinit {
        if let context { whisper_free(context) }
    }

    /// Transcribe an M4A audio file, extracting the left channel (system audio).
    /// - Parameters:
    ///   - audioURL: Path to the M4A recording.
    ///   - progressCallback: Called with progress 0.0–1.0 on a background thread.
    /// - Returns: Array of transcript segments with timing.
    func transcribe(
        audioURL: URL,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        guard let context else { throw WhisperError.modelNotLoaded }

        // Convert M4A → 16kHz mono Float32 PCM (left channel only)
        let samples = try await convertAudioToWhisperFormat(audioURL: audioURL)

        // Run inference on a background thread
        let ctx = context
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[TranscriptSegment], Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let segments = try Self.runInference(
                        context: ctx,
                        samples: samples,
                        progressCallback: progressCallback
                    )
                    continuation.resume(returning: segments)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Convert an M4A file to 16kHz mono Float32 PCM, extracting the left channel.
    private func convertAudioToWhisperFormat(audioURL: URL) async throws -> [Float] {
        let sourceFile = try AVAudioFile(forReading: audioURL)
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFile.fileFormat.sampleRate,
            channels: sourceFile.fileFormat.channelCount,
            interleaved: false
        ) else {
            throw WhisperError.audioConversionFailed
        }

        // Read all samples from source
        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw WhisperError.audioConversionFailed
        }
        try sourceFile.read(into: sourceBuffer)

        // Target: 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperError.audioConversionFailed
        }

        // Extract left channel (channel 0 = system audio) into a mono buffer
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFile.fileFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount) else {
            throw WhisperError.audioConversionFailed
        }
        monoBuffer.frameLength = sourceBuffer.frameLength

        if let srcData = sourceBuffer.floatChannelData, let dstData = monoBuffer.floatChannelData {
            // Copy left channel
            dstData[0].update(from: srcData[0], count: Int(sourceBuffer.frameLength))
        }

        // Resample to 16kHz
        guard let converter = AVAudioConverter(from: monoFormat, to: targetFormat) else {
            throw WhisperError.audioConversionFailed
        }

        let ratio = 16000.0 / sourceFile.fileFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(monoBuffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            throw WhisperError.audioConversionFailed
        }

        // Use a class wrapper to satisfy Sendable requirements in Swift 6
        final class DoneFlag: @unchecked Sendable {
            var value = false
        }
        let doneFlag = DoneFlag()
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if doneFlag.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            doneFlag.value = true
            outStatus.pointee = .haveData
            return monoBuffer
        }

        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if let conversionError { throw conversionError }

        // Extract Float array
        guard let channelData = outputBuffer.floatChannelData else {
            throw WhisperError.audioConversionFailed
        }
        let count = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    /// Run whisper inference synchronously (call from background thread only).
    private static func runInference(
        context: OpaquePointer,
        samples: [Float],
        progressCallback: (@Sendable (Double) -> Void)?
    ) throws -> [TranscriptSegment] {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        let langPtr = strdup("en")
        params.language = UnsafePointer(langPtr)
        params.translate = false

        // Progress callback via whisper's new_segment_callback
        // We approximate progress based on processed audio duration
        let totalDuration = Double(samples.count) / 16000.0

        struct ProgressContext {
            let totalDuration: Double
            let callback: (@Sendable (Double) -> Void)?
        }

        let progressCtx = ProgressContext(totalDuration: totalDuration, callback: progressCallback)
        let progressPtr = UnsafeMutablePointer<ProgressContext>.allocate(capacity: 1)
        progressPtr.initialize(to: progressCtx)
        defer {
            progressPtr.deinitialize(count: 1)
            progressPtr.deallocate()
        }

        params.new_segment_callback_user_data = UnsafeMutableRawPointer(progressPtr)
        params.new_segment_callback = { (ctx, _state, nNew, userData) in
            guard let ctx, let userData else { return }
            let pCtx = userData.assumingMemoryBound(to: ProgressContext.self).pointee
            let nSegments = whisper_full_n_segments(ctx)
            if nSegments > 0 {
                let lastEnd = whisper_full_get_segment_t1(ctx, nSegments - 1)
                let progress = min(1.0, Double(lastEnd) / 100.0 / pCtx.totalDuration)
                pCtx.callback?(progress)
            }
        }

        let result = samples.withUnsafeBufferPointer { ptr in
            whisper_full(context, params, ptr.baseAddress, Int32(samples.count))
        }

        if let langPtr { free(langPtr) }

        guard result == 0 else {
            throw WhisperError.inferenceFailed
        }

        // Extract segments
        let nSegments = whisper_full_n_segments(context)
        var segments: [TranscriptSegment] = []
        segments.reserveCapacity(Int(nSegments))

        for i in 0..<nSegments {
            let startTime = Double(whisper_full_get_segment_t0(context, i)) / 100.0
            let endTime = Double(whisper_full_get_segment_t1(context, i)) / 100.0
            let text = String(cString: whisper_full_get_segment_text(context, i))
            segments.append(TranscriptSegment(startTime: startTime, endTime: endTime, text: text))
        }

        progressCallback?(1.0)
        return segments
    }
}

enum WhisperError: LocalizedError {
    case modelNotFound
    case modelLoadFailed
    case modelNotLoaded
    case audioConversionFailed
    case inferenceFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Whisper model file not found."
        case .modelLoadFailed: return "Failed to load Whisper model."
        case .modelNotLoaded: return "Whisper model is not loaded."
        case .audioConversionFailed: return "Failed to convert audio to Whisper format."
        case .inferenceFailed: return "Whisper inference failed."
        }
    }
}
