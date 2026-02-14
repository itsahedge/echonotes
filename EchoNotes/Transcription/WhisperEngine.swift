import Foundation
@preconcurrency import AVFoundation
import CWhisper
import os

/// Wraps the whisper.cpp C API to perform speech-to-text on audio files.
/// All inference runs off the main thread to keep the UI responsive.
final class WhisperEngine: @unchecked Sendable {
    private var context: OpaquePointer?
    private let isRunning = OSAllocatedUnfairLock(initialState: false)

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

        // Prevent concurrent inference
        let acquired = isRunning.withLock { running -> Bool in
            if running { return false }
            running = true
            return true
        }
        guard acquired else { throw WhisperError.inferenceFailed }

        defer {
            isRunning.withLock { $0 = false }
        }

        // Convert M4A → 16kHz mono Float32 PCM (left channel only)
        let samples = try await convertAudioToWhisperFormat(audioURL: audioURL)

        // Run inference off the main thread
        let ctx = context
        return try await Task.detached(priority: .userInitiated) {
            try Self.runInference(
                context: ctx,
                samples: samples,
                progressCallback: progressCallback
            )
        }.value
    }

    /// Convert an M4A file to 16kHz mono Float32 PCM, extracting the left channel.
    /// Processes audio in chunks to avoid holding the entire file in memory.
    private func convertAudioToWhisperFormat(audioURL: URL) async throws -> [Float] {
        let sourceFile = try AVAudioFile(forReading: audioURL)
        let sourceSampleRate = sourceFile.fileFormat.sampleRate
        let totalFrames = sourceFile.length

        // Source format for reading as Float32
        let sourceChannelCount = sourceFile.fileFormat.channelCount
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: sourceChannelCount,
            interleaved: false
        ) else {
            throw WhisperError.audioConversionFailed
        }

        // Mono format at source sample rate (for left channel extraction)
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        )!

        // Target: 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperError.audioConversionFailed
        }

        guard let converter = AVAudioConverter(from: monoFormat, to: targetFormat) else {
            throw WhisperError.audioConversionFailed
        }

        let ratio = 16000.0 / sourceSampleRate
        let estimatedOutputFrames = Int(Double(totalFrames) * ratio) + 1024
        var outputSamples = [Float]()
        outputSamples.reserveCapacity(estimatedOutputFrames)

        // Process in chunks of 64K frames (~1.3s at 48kHz)
        let chunkSize: AVAudioFrameCount = 65536
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: chunkSize) else {
            throw WhisperError.audioConversionFailed
        }
        guard let monoChunk = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: chunkSize) else {
            throw WhisperError.audioConversionFailed
        }

        let outputChunkCapacity = AVAudioFrameCount(Double(chunkSize) * ratio) + 256
        guard let outputChunk = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputChunkCapacity) else {
            throw WhisperError.audioConversionFailed
        }

        final class DoneFlag: @unchecked Sendable {
            var value = false
        }
        let doneFlag = DoneFlag()

        var framesRead: AVAudioFramePosition = 0
        while framesRead < totalFrames {
            let framesToRead = min(chunkSize, AVAudioFrameCount(totalFrames - framesRead))
            readBuffer.frameLength = 0
            try sourceFile.read(into: readBuffer, frameCount: framesToRead)

            guard readBuffer.frameLength > 0 else { break }

            // Extract left channel into mono chunk
            monoChunk.frameLength = readBuffer.frameLength
            if let srcData = readBuffer.floatChannelData, let dstData = monoChunk.floatChannelData {
                dstData[0].update(from: srcData[0], count: Int(readBuffer.frameLength))
            }

            // Resample chunk to 16kHz
            doneFlag.value = false
            let chunkRef = monoChunk
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if doneFlag.value {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                doneFlag.value = true
                outStatus.pointee = .haveData
                return chunkRef
            }

            outputChunk.frameLength = 0
            var conversionError: NSError?
            converter.convert(to: outputChunk, error: &conversionError, withInputFrom: inputBlock)
            if let conversionError { throw conversionError }

            if let channelData = outputChunk.floatChannelData {
                let count = Int(outputChunk.frameLength)
                outputSamples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: count))
            }

            framesRead += AVAudioFramePosition(readBuffer.frameLength)
        }

        return outputSamples
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
            var lastReportedProgress: Double
            var lastReportedTime: UInt64
        }

        let progressCtx = ProgressContext(
            totalDuration: totalDuration,
            callback: progressCallback,
            lastReportedProgress: 0,
            lastReportedTime: DispatchTime.now().uptimeNanoseconds
        )
        let progressPtr = UnsafeMutablePointer<ProgressContext>.allocate(capacity: 1)
        progressPtr.initialize(to: progressCtx)
        defer {
            progressPtr.deinitialize(count: 1)
            progressPtr.deallocate()
        }

        params.new_segment_callback_user_data = UnsafeMutableRawPointer(progressPtr)
        params.new_segment_callback = { (ctx, _state, nNew, userData) in
            guard let ctx, let userData else { return }
            let pCtxPtr = userData.assumingMemoryBound(to: ProgressContext.self)
            let nSegments = whisper_full_n_segments(ctx)
            if nSegments > 0 {
                let lastEnd = whisper_full_get_segment_t1(ctx, nSegments - 1)
                let progress = min(1.0, Double(lastEnd) / 100.0 / pCtxPtr.pointee.totalDuration)
                // Throttle: only report if progress changed by ≥2% or 200ms elapsed
                let now = DispatchTime.now().uptimeNanoseconds
                let elapsed = now - pCtxPtr.pointee.lastReportedTime
                let delta = progress - pCtxPtr.pointee.lastReportedProgress
                if delta >= 0.02 || elapsed >= 200_000_000 {
                    pCtxPtr.pointee.lastReportedProgress = progress
                    pCtxPtr.pointee.lastReportedTime = now
                    pCtxPtr.pointee.callback?(progress)
                }
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
