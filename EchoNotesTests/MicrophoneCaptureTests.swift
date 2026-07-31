import Testing
import AVFoundation
import os
@testable import EchoNotes

@Suite("MicrophoneCapture Tests")
struct MicrophoneCaptureTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    @Test("clearWarning resets warning state")
    func clearWarningResetsState() {
        let capture = MicrophoneCapture()

        #expect(!capture.hasWarning)
        capture.clearWarning()
        #expect(!capture.hasWarning)
    }

    @Test("start handles missing device gracefully")
    func startWithNoDevice() async throws {
        let capture = MicrophoneCapture()
        let received = OSAllocatedUnfairLock(initialState: false)

        capture.onWarning = { _ in
            received.withLock { $0 = true }
        }

        // If no device is available, capture enters the silence-feed state
        // with a warning instead of failing. Either outcome (device found or
        // warning) is valid depending on the test machine.
        do {
            try capture.start(writingTo: tempDir.appendingPathComponent("mic.caf"))
            try await Task.sleep(for: .milliseconds(100))
            capture.stopCapture()
        } catch {
            capture.stopCapture()
        }
    }

    @Test("stopCapture cleans up and is idempotent")
    func stopCaptureCleansUp() async throws {
        let capture = MicrophoneCapture()

        for i in 0..<3 {
            do {
                try capture.start(writingTo: tempDir.appendingPathComponent("mic-\(i).caf"))
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                // Start can fail without a device or permission — still must clean up.
            }
            capture.stopCapture()
            capture.stopCapture() // second call must be a no-op
        }
    }

    @Test("pause before start is a no-op")
    func pauseBeforeStart() {
        let capture = MicrophoneCapture()
        capture.pauseCapture()
        #expect(capture.firstBufferAt == nil)
    }

    @Test("start writes a readable CAF file")
    func startCreatesFile() async throws {
        let capture = MicrophoneCapture()
        let url = tempDir.appendingPathComponent("mic.caf")

        do {
            try capture.start(writingTo: url)
        } catch {
            // No device/permission in this environment — nothing to assert.
            return
        }
        try await Task.sleep(for: .milliseconds(200))
        capture.stopCapture()

        #expect(FileManager.default.fileExists(atPath: url.path))
        // CAF needs no finalization pass — the file must be readable as-is.
        let file = try AVAudioFile(forReading: url)
        #expect(file.processingFormat.channelCount == 1)
    }
}
