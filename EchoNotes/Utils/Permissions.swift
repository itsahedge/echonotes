import AVFoundation
import ScreenCaptureKit

/// Checks and requests macOS permissions for mic + system audio recording.
///
/// **Note:** "Screen Recording" permission is required to use ScreenCaptureKit's audio API.
/// We use ScreenCaptureKit in AUDIO-ONLY mode — no video, screen, or visual data is captured.
struct PermissionChecker {
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func requestScreenRecordingPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch { return false }
    }

    func ensureAllPermissions() async -> Bool {
        let mic = await requestMicrophonePermission()
        let screen = await requestScreenRecordingPermission()
        return mic && screen
    }
    
    /// Check permissions individually and return a specific error message if any are missing.
    func checkPermissionsWithMessage() async -> String? {
        let mic = await requestMicrophonePermission()
        let screen = await requestScreenRecordingPermission()
        
        if !mic && !screen {
            return """
            EchoNotes needs Microphone and Screen Recording permissions.
            
            Enable them in: System Settings → Privacy & Security → Microphone & Screen Recording
            """
        } else if !mic {
            return """
            EchoNotes needs Microphone permission.
            
            Enable it in: System Settings → Privacy & Security → Microphone
            """
        } else if !screen {
            return """
            EchoNotes needs Screen Recording permission (for system audio capture only — no video is recorded).
            
            Enable it in: System Settings → Privacy & Security → Screen Recording
            """
        }
        
        return nil
    }
}
