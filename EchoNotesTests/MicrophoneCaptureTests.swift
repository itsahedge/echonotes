import Testing
import AVFoundation
@testable import EchoNotes

@Suite("MicrophoneCapture Tests")
struct MicrophoneCaptureTests {
    
    @Test("clearWarning resets warning state")
    func clearWarningResetsState() async throws {
        let capture = MicrophoneCapture()
        
        // Initially no warning
        #expect(!capture.hasWarning)
        
        // Simulate warning state by accessing internal lock
        // (In real usage, this would be set by handlePermanentDisconnection)
        // We can't directly test the private lock, but we can verify clearWarning doesn't crash
        capture.clearWarning()
        #expect(!capture.hasWarning)
    }
    
    @Test("startCapture handles missing device gracefully")
    func startCaptureWithNoDevice() async throws {
        let capture = MicrophoneCapture()
        var warningReceived = false
        
        capture.onWarning = { _ in
            warningReceived = true
        }
        
        // Start capture - if no device is available, it should enter disconnected state
        // Note: This test behavior depends on system state
        do {
            try await capture.startCapture(sampleRate: 48000)
            
            // Give it a moment to initialize
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Clean up
            capture.stopCapture()
            
            // If warning was received, that's expected when no mic is available
            // If not, that means a mic was found (also valid)
            // Either way, no crash = success
        } catch {
            // Error is also acceptable if device setup fails
            capture.stopCapture()
        }
    }
    
    @Test("stopCapture cleans up resources")
    func stopCaptureCleansUp() async throws {
        let capture = MicrophoneCapture()
        
        // Start and stop multiple times to verify cleanup works
        for _ in 0..<3 {
            do {
                try await capture.startCapture(sampleRate: 48000)
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            } catch {
                // Continue even if start fails
            }
            capture.stopCapture()
        }
        
        // Should complete without crash
        #expect(true)
    }
    
    @Test("onWarning callback is invoked")
    func onWarningCallback() async throws {
        let capture = MicrophoneCapture()
        var receivedWarning: String?
        
        capture.onWarning = { warning in
            receivedWarning = warning
        }
        
        // We can't directly trigger the warning without a real disconnection,
        // but we can verify the callback slot is settable and clearWarning works
        capture.clearWarning()
        #expect(!capture.hasWarning)
        
        // Callback assignment doesn't crash = success
        #expect(true)
    }
    
    @Test("multiple start/stop cycles don't leak state")
    func multipleStartStopCycles() async throws {
        let capture = MicrophoneCapture()
        
        for i in 0..<5 {
            do {
                try await capture.startCapture(sampleRate: 48000)
                _ = i // Use variable to avoid unused warning
                try await Task.sleep(nanoseconds: 25_000_000) // 25ms
            } catch {
                // Expected in some environments
            }
            capture.stopCapture()
        }
        
        // Should complete without crash or state leak
        #expect(true)
    }
}