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
}
