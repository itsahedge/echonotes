import Foundation
import SwiftUI
import AppKit
import AVFoundation
import os

/// Central recording engine — coordinates system audio + mic capture and writes to file.
///
/// **Error Handling Strategy:**
/// - **Audio capture layer** (SystemAudioCapture, MicrophoneCapture): Uses closures (`onError`)
///   to propagate errors asynchronously from background threads.
/// - **Recording engine**: Surfaces errors via `@Published var errorMessage` for UI binding.
/// - **Transcription layer**: Uses throwing functions for synchronous errors, publishes async
///   errors via TranscriptionManager's `@Published var error`.
///
/// This mixed approach matches the concurrency model: audio callbacks need async propagation,
/// while engine state changes are published to UI observers, and transcription operations
/// use structured concurrency with throws.
@MainActor
final class RecordingEngine: ObservableObject {
    private let logger = Logger(subsystem: "com.echonotes", category: "RecordingEngine")
    private var debugLog: DebugLogger { DebugLogger.shared }
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0
    @Published var errorMessage: String?
    @Published var lastRecordingURL: URL?
    @Published var isPaused: Bool = false
    /// Total time spent paused across all pause/resume cycles in the current recording.
    @Published var totalPauseDuration: TimeInterval = 0
    @Published var autoTranscribe: Bool = UserDefaults.standard.bool(forKey: "autoTranscribe") {
        didSet { UserDefaults.standard.set(autoTranscribe, forKey: "autoTranscribe") }
    }
    @Published var transcriptionModeRaw: String = UserDefaults.standard.string(forKey: "transcriptionMode") ?? TranscriptionMode.postRecording.rawValue {
        didSet { UserDefaults.standard.set(transcriptionModeRaw, forKey: "transcriptionMode") }
    }
    @Published var selectedSourceId: String = UserDefaults.standard.string(forKey: "selectedMicrophone") ?? "" {
        didSet { UserDefaults.standard.set(selectedSourceId, forKey: "selectedMicrophone") }
    }
    @Published var selectedSystemSourceId: String = UserDefaults.standard.string(forKey: "selectedSystemSource") ?? "" {
        didSet { UserDefaults.standard.set(selectedSystemSourceId, forKey: "selectedSystemSource") }
    }
    
    var availableSources: [String] {
        MicrophoneCapture.availableDevices()
    }
    
    var availableSystemSources: [String] {
        SystemAudioCapture.availableDevices()
    }

    var transcriptionMode: TranscriptionMode {
        get { TranscriptionMode(rawValue: transcriptionModeRaw) ?? .postRecording }
        set { transcriptionModeRaw = newValue.rawValue }
    }

    let transcriptionManager = TranscriptionManager()

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicrophoneCapture()
    private var audioWriter: AudioFileWriter?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var pauseStartTime: Date?
    /// Accumulated pause time from previous pause/resume cycles (not including current pause).
    private var accumulatedPauseDuration: TimeInterval = 0
    private var lastSystemLevelUpdate: Date = .distantPast
    private var lastMicLevelUpdate: Date = .distantPast
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// Reusable DateFormatter for recording filenames. Static to avoid repeated allocation.
    private static let recordingTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Save location for recordings. Directory validation happens in startRecording().
    var saveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("EchoNotes", isDirectory: true)
    }

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil
        // Clear any previous microphone warnings
        micCapture.clearWarning()

        // Check permissions
        if let permissionError = await PermissionChecker.checkPermissionsWithMessage() {
            errorMessage = permissionError
            return
        }

        // Ensure recordings directory exists
        do {
            try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Failed to create recordings directory: \(error.localizedDescription)"
            return
        }

        // Check available disk space before recording
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: saveDirectory.path)
            if let freeSpace = attrs[.systemFreeSize] as? Int64, freeSpace < 500 * 1024 * 1024 {
                let freeMB = freeSpace / (1024 * 1024)
                errorMessage = "Low disk space (\(freeMB) MB free). At least 500 MB recommended for recording."
                return
            }
        } catch {
            logger.warning("Could not check disk space: \(error.localizedDescription)")
        }

        // Create output file with local timezone timestamp
        let timestamp = Self.recordingTimestampFormatter.string(from: Date())
        let filename = "recording-\(timestamp).m4a"
        let fileURL = saveDirectory.appendingPathComponent(filename)

        do {
            // Set up audio file writer (M4A/AAC, 48kHz stereo — system L, mic R)
            let writer = try AudioFileWriter(outputURL: fileURL, sampleRate: AudioConfig.sampleRate, channels: 2) { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "Recording error: \(error.localizedDescription)"
                    await self?.stopRecording()
                }
            }

            audioWriter = writer

            // Clear any previous microphone warnings
            micCapture.clearWarning()

            // Surface audio capture errors to the UI
            systemCapture.onError = { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "System audio error: \(error.localizedDescription)"
                    await self?.stopRecording()
                }
            }

            micCapture.onWarning = { [weak self] message in
                Task { @MainActor in
                    self?.errorMessage = message
                }
            }

            micCapture.onError = { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "Microphone error: \(error.localizedDescription)"
                    await self?.stopRecording()
                }
            }

            // Surface microphone warnings (non-fatal, recording continues)
            micCapture.onWarning = { [weak self] warning in
                Task { @MainActor in
                    // Don't overwrite existing errors with warnings
                    if self?.errorMessage == nil {
                        self?.errorMessage = warning
                    }
                }
            }

            // Set up live transcription if enabled
            let isLive = transcriptionMode == .live
            if isLive {
                do {
                    try await transcriptionManager.prepareForLiveTranscription()
                    transcriptionManager.streamingTranscriber.reset()
                } catch {
                    errorMessage = "Failed to prepare live transcription: \(error.localizedDescription)"
                    cleanup()
                    return
                }
            }

            // Start both captures BEFORE setting onBuffer callbacks
            // This prevents partial failure states where system buffers feed a writer
            // that's about to be finalized
            try await systemCapture.startCapture(sampleRate: AudioConfig.sampleRate)
            do {
                try micCapture.startCapture(sampleRate: AudioConfig.sampleRate)
            } catch {
                // System capture already started — must stop it before bailing
                await systemCapture.stopCapture()
                throw error
            }

            // Capture references for use in audio callbacks. These callbacks fire on
            // background threads (ScreenCaptureKit / AVAudioEngine). Accessing them
            // through `self` would hit the @MainActor executor check and crash.
            // Both types use internal locking and are safe to call from any thread.
            let writerRef = writer
            let transcriberRef = isLive ? transcriptionManager.streamingTranscriber : nil

            // Now that both captures are running, set up buffer callbacks
            systemCapture.onBuffer = { [weak self] buffer in
                writerRef.writeSystemBuffer(buffer)
                transcriberRef?.feedSamples(buffer.samples)
                // Throttle level meter updates to ~15fps (66ms minimum interval)
                Task { @MainActor in
                    guard let self else { return }
                    let now = Date()
                    if now.timeIntervalSince(self.lastSystemLevelUpdate) > 0.066 {
                        self.systemLevel = SourcedAudioBuffer.rmsLevel(buffer.samples)
                        self.lastSystemLevelUpdate = now
                    }
                }
            }

            micCapture.onBuffer = { [weak self] buffer in
                writerRef.writeMicBuffer(buffer)
                // Throttle level meter updates to ~15fps (66ms minimum interval)
                Task { @MainActor in
                    guard let self else { return }
                    let now = Date()
                    if now.timeIntervalSince(self.lastMicLevelUpdate) > 0.066 {
                        self.micLevel = SourcedAudioBuffer.rmsLevel(buffer.samples)
                        self.lastMicLevelUpdate = now
                    }
                }
            }

            lastRecordingURL = fileURL
            recordingStartTime = Date()
            isRecording = true
            installSleepWakeObservers()
            logger.info("Recording started: \(fileURL.lastPathComponent)")
            debugLog.info("Recording started: \(fileURL.lastPathComponent)", category: "Recording")

            // Duration timer — shows actual recording time (wall clock minus total pause time)
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let start = self.recordingStartTime else { return }
                    let elapsed = Date().timeIntervalSince(start)
                    self.duration = elapsed - self.totalPauseDuration
                }
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            audioWriter?.finalize()
            cleanup()
        }
    }

    /// Pause recording — stops audio capture but keeps the file open for later resume.
    func pause() async {
        guard isRecording && !isPaused else { return }

        logger.info("Pausing recording...")
        isPaused = true
        pauseStartTime = Date()

        // Stop duration timer while paused (prevents timer drift during pause)
        durationTimer?.invalidate()
        durationTimer = nil

        // Stop audio captures
        await systemCapture.stopCapture()
        micCapture.stopCapture()

        // Reset level meters
        systemLevel = 0
        micLevel = 0

        // Pause live transcription if enabled
        if transcriptionMode == .live {
            await transcriptionManager.pauseLiveTranscription()
        }
    }

    /// Resume recording — restarts audio capture, accumulates pause duration.
    func resume() async {
        guard isRecording && isPaused else { return }

        logger.info("Resuming recording...")

        // Accumulate this pause cycle's duration
        if let pauseStart = pauseStartTime {
            let thisPause = Date().timeIntervalSince(pauseStart)
            accumulatedPauseDuration += thisPause
            totalPauseDuration = accumulatedPauseDuration
        }
        isPaused = false
        pauseStartTime = nil

        // Resume audio captures
        // Note: onBuffer callbacks survive because they're set as properties on the
        // capture objects, not on the SCStream/AVAudioEngine instances that get recreated.
        do {
            try await systemCapture.startCapture(sampleRate: AudioConfig.sampleRate)
        } catch {
            logger.error("Failed to resume system audio: \(error.localizedDescription)")
            errorMessage = "Failed to resume system audio: \(error.localizedDescription)"
            return
        }

        do {
            try micCapture.startCapture(sampleRate: AudioConfig.sampleRate)
        } catch {
            logger.error("Failed to resume microphone: \(error.localizedDescription)")
            errorMessage = "Failed to resume microphone: \(error.localizedDescription)"
            await systemCapture.stopCapture()
            return
        }

        // Restart duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.duration = elapsed - self.totalPauseDuration
            }
        }

        // Resume live transcription if enabled
        if transcriptionMode == .live {
            await transcriptionManager.resumeLiveTranscription()
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        removeSleepWakeObservers()
        durationTimer?.invalidate()
        durationTimer = nil

        // If currently paused, captures are already stopped — skip redundant stop calls
        if !isPaused {
            await systemCapture.stopCapture()
            micCapture.stopCapture()
        }
        audioWriter?.finalize()

        let url = audioWriter?.outputURL
        let recordedDuration = duration  // Capture before reset
        cleanup()

        isRecording = false
        isPaused = false
        duration = 0
        totalPauseDuration = 0
        accumulatedPauseDuration = 0
        pauseStartTime = nil
        micLevel = 0
        systemLevel = 0

        if let url {
            lastRecordingURL = url
            logger.info("Recording stopped: \(url.lastPathComponent), duration: \(String(format: "%.1f", recordedDuration))s")
            debugLog.info("Recording stopped: \(url.lastPathComponent) (\(String(format: "%.1f", recordedDuration))s)", category: "Recording")

            if transcriptionMode == .live {
                // Finalize live transcription — flush remaining chunks
                await transcriptionManager.finalizeLiveTranscription(recordingURL: url)
            } else {
                transcriptionManager.reset()
                // Auto-transcribe if enabled (post-recording mode)
                if autoTranscribe {
                    Task { await transcriptionManager.transcribe(audioURL: url) }
                }
            }
        }
    }

    // MARK: - Sleep/Wake Handling

    /// Install observers to auto-pause recording when the system sleeps.
    /// Prevents audio subsystems from entering a stale state during sleep.
    private func installSleepWakeObservers() {
        guard sleepObserver == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter

        sleepObserver = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRecording, !self.isPaused else { return }
                self.logger.info("System going to sleep — auto-pausing recording")
                await self.pause()
                self.errorMessage = "Recording paused — system went to sleep. Tap Resume to continue."
            }
        }

        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRecording, self.isPaused else { return }
                // Don't auto-resume; let the user decide when to continue.
                // The pause message from sleep handler is already visible.
                self.logger.info("System woke up — recording remains paused, waiting for user to resume")
            }
        }
    }

    private func removeSleepWakeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        if let observer = sleepObserver {
            workspace.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = wakeObserver {
            workspace.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private func cleanup() {
        audioWriter = nil
        recordingStartTime = nil
    }
}
