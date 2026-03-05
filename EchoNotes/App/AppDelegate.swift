import AppKit
import SwiftUI

/// Application delegate — owns shared state objects.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let recorder = RecordingEngine()
    let library = RecordingLibrary()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-download Whisper model on first launch if not already cached
        Task {
            if !ModelManager.modelLikelyCached() {
                _ = try? await recorder.transcriptionManager.modelManager.ensureEngine(
                    for: recorder.transcriptionManager.selectedModel
                )
            }
        }
    }
}
