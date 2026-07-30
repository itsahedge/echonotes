import Foundation
import SwiftUI
import AppKit
import AVFoundation
import os

/// Central recording engine — coordinates a RecordingSession (mic + system
/// tracks) and surfaces state to the UI.
///
/// **Error Handling Strategy:**
/// - **Audio capture layer** (SystemAudioCapture, MicrophoneCapture): Uses closures (`onError`)
///   to propagate errors asynchronously from background threads.
/// - **Recording engine**: Surfaces errors via the observable `errorMessage` for UI binding.
/// - **Transcription layer**: Uses throwing functions for synchronous errors, publishes async
///   errors via TranscriptionManager's observable `error`.
///
/// This mixed approach matches the concurrency model: audio callbacks need async propagation,
/// while engine state changes are published to UI observers, and transcription operations
/// use structured concurrency with throws.
@MainActor
@Observable
final class RecordingEngine {
    @ObservationIgnored private let logger = Logger(subsystem: "com.echonotes", category: "RecordingEngine")
    @ObservationIgnored private var debugLog: DebugLogger { DebugLogger.shared }
    var isRecording = false
    var duration: TimeInterval = 0
    var micLevel: Float = 0
    var systemLevel: Float = 0
    var errorMessage: String?
    var lastRecordingURL: URL?
    var isPaused: Bool = false
    /// Total time spent paused across all pause/resume cycles in the current recording.
    var totalPauseDuration: TimeInterval = 0
    var autoTranscribe: Bool = UserDefaults.standard.bool(forKey: "autoTranscribe") {
        didSet { UserDefaults.standard.set(autoTranscribe, forKey: "autoTranscribe") }
    }
    var transcriptionModeRaw: String = UserDefaults.standard.string(forKey: "transcriptionMode") ?? TranscriptionMode.postRecording.rawValue {
        didSet { UserDefaults.standard.set(transcriptionModeRaw, forKey: "transcriptionMode") }
    }
    var selectedSourceId: String = UserDefaults.standard.string(forKey: "selectedMicrophone") ?? "" {
        didSet { UserDefaults.standard.set(selectedSourceId, forKey: "selectedMicrophone") }
    }
    var selectedSystemSourceId: String = UserDefaults.standard.string(forKey: "selectedSystemSource") ?? "" {
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

    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var durationTimer: Timer?
    @ObservationIgnored private var recordingStartTime: Date?
    @ObservationIgnored private var pauseStartTime: Date?
    @ObservationIgnored private var accumulatedPauseDuration: TimeInterval = 0
    @ObservationIgnored private var lastSystemLevelUpdate: Date = .distantPast
    @ObservationIgnored private var lastMicLevelUpdate: Date = .distantPast
    @ObservationIgnored private let systemLevelUpdateGate = OSAllocatedUnfairLock(initialState: Date.distantPast)
    @ObservationIgnored private let micLevelUpdateGate = OSAllocatedUnfairLock(initialState: Date.distantPast)
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// Save location for recordings. Directory validation happens in startRecording().
    var saveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("EchoNotes", isDirectory: true)
    }

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil

        // Check permissions (microphone; system audio prompts at tap creation)
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

        // Set up live transcription if enabled
        let isLive = transcriptionMode == .live
        if isLive {
            do {
                try await transcriptionManager.prepareForLiveTranscription()
                transcriptionManager.streamingTranscriber.reset()
            } catch {
                errorMessage = "Failed to prepare live transcription: \(error.localizedDescription)"
                return
            }
        }

        do {
            let newSession = try RecordingSession(root: saveDirectory)
            newSession.mic.clearWarning()

            // Surface audio capture errors to the UI
            newSession.system.onError = { [weak self] error in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.errorMessage = "System audio error: \(error.localizedDescription)"
                    await self.stopRecording()
                }
            }

            newSession.mic.onError = { [weak self] error in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.errorMessage = "Microphone error: \(error.localizedDescription)"
                    await self.stopRecording()
                }
            }

            // Surface microphone warnings (non-fatal, recording continues).
            // Don't overwrite existing errors with warnings.
            newSession.mic.onWarning = { [weak self] warning in
                Task { @MainActor in
                    if self?.errorMessage == nil {
                        self?.errorMessage = warning
                    }
                }
            }

            try newSession.start()

            // Capture references for use in audio callbacks. These callbacks
            // fire on background threads (Core Audio / AVAudioEngine), so they
            // must not touch @MainActor state directly.
            let transcriberRef = isLive ? transcriptionManager.streamingTranscriber : nil
            let systemLevelUpdateGate = self.systemLevelUpdateGate
            let micLevelUpdateGate = self.micLevelUpdateGate
            systemLevelUpdateGate.withLock { $0 = .distantPast }
            micLevelUpdateGate.withLock { $0 = .distantPast }

            // Recorders write their own files; these callbacks only drive
            // level meters and live transcription.
            newSession.system.onBuffer = { [weak self] buffer in
                transcriberRef?.feedSamples(buffer.samples)
                let now = Date()
                guard RecordingEngine.shouldScheduleLevelUpdate(using: systemLevelUpdateGate, at: now) else { return }
                let level = SourcedAudioBuffer.rmsLevel(buffer.samples)

                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.systemLevel = level
                    self.lastSystemLevelUpdate = now
                }
            }

            newSession.mic.onBuffer = { [weak self] buffer in
                let now = Date()
                guard RecordingEngine.shouldScheduleLevelUpdate(using: micLevelUpdateGate, at: now) else { return }
                let level = SourcedAudioBuffer.rmsLevel(buffer.samples)

                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.micLevel = level
                    self.lastMicLevelUpdate = now
                }
            }

            session = newSession
            lastRecordingURL = newSession.dir
            recordingStartTime = Date()
            isRecording = true
            installSleepWakeObservers()
            logger.info("Recording started: \(newSession.dir.lastPathComponent)")
            debugLog.info("Recording started: \(newSession.dir.lastPathComponent)", category: "Recording")

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
            cleanup()
        }
    }

    /// Pause recording — stops audio capture but keeps both files open for resume.
    func pause() async {
        guard isRecording && !isPaused, let session else { return }

        logger.info("Pausing recording...")
        isPaused = true
        pauseStartTime = Date()

        // Stop duration timer while paused (prevents timer drift during pause)
        durationTimer?.invalidate()
        durationTimer = nil

        session.pause()

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
        guard isRecording && isPaused, let session else { return }

        logger.info("Resuming recording...")

        do {
            try session.resume()
        } catch {
            logger.error("Failed to resume recording: \(error.localizedDescription)")
            errorMessage = "Failed to resume recording: \(error.localizedDescription)"
            return
        }

        // Accumulate this pause cycle's duration
        if let pauseStart = pauseStartTime {
            let thisPause = Date().timeIntervalSince(pauseStart)
            accumulatedPauseDuration += thisPause
            totalPauseDuration = accumulatedPauseDuration
        }
        isPaused = false
        pauseStartTime = nil

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
        guard isRecording, let session else { return }

        removeSleepWakeObservers()
        durationTimer?.invalidate()
        durationTimer = nil

        let recordedDuration = duration  // Capture before reset
        session.stop(recordedDuration: recordedDuration)
        let dir = session.dir
        cleanup()

        isRecording = false
        isPaused = false
        duration = 0
        totalPauseDuration = 0
        accumulatedPauseDuration = 0
        pauseStartTime = nil
        micLevel = 0
        systemLevel = 0

        lastRecordingURL = dir
        logger.info("Recording stopped: \(dir.lastPathComponent), duration: \(String(format: "%.1f", recordedDuration))s")
        debugLog.info("Recording stopped: \(dir.lastPathComponent) (\(String(format: "%.1f", recordedDuration))s)", category: "Recording")

        if transcriptionMode == .live {
            // Finalize live transcription — flush remaining chunks
            await transcriptionManager.finalizeLiveTranscription(recordingURL: dir)
        } else {
            transcriptionManager.reset()
            // Auto-transcribe if enabled (post-recording mode)
            if autoTranscribe {
                transcriptionManager.enqueue(dir)
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
        session = nil
        recordingStartTime = nil
    }

    nonisolated private static func shouldScheduleLevelUpdate(
        using gate: OSAllocatedUnfairLock<Date>,
        at now: Date
    ) -> Bool {
        gate.withLock { lastUpdate in
            guard now.timeIntervalSince(lastUpdate) >= 0.066 else { return false }
            lastUpdate = now
            return true
        }
    }
}
