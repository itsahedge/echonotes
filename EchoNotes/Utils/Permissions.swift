import AVFoundation

/// Checks and requests macOS permissions for recording.
///
/// Only the microphone can be checked up front. System audio capture (Core
/// Audio process tap) has no side-effect-free TCC query: macOS prompts once
/// at first tap creation, and a denial surfaces as a descriptive error from
/// SystemAudioCapture.start with remediation steps.
struct PermissionChecker {
    private static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Check permissions and return a specific error message if any are missing.
    static func checkPermissionsWithMessage() async -> String? {
        guard await requestMicrophonePermission() else {
            return """
            EchoNotes needs Microphone permission.

            Enable it in: System Settings → Privacy & Security → Microphone
            """
        }
        return nil
    }
}
