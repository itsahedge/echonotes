import AppKit
import SwiftUI

/// Application delegate — owns shared state objects.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let recorder = RecordingEngine()
    let library = RecordingLibrary()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let debugLog = DebugLogger.shared
        let tm = recorder.transcriptionManager
        debugLog.info("EchoNotes launched", category: "App")
        debugLog.info("Whisper model: \(tm.selectedModel.rawValue)", category: "App")
        debugLog.info("AI provider: \(tm.selectedProvider.rawValue) (\(tm.selectedAIModel))", category: "App")
        if tm.useKnowledgeBase && !tm.knowledgeBasePath.isEmpty {
            debugLog.info("Knowledge base: \(tm.knowledgeBasePath)", category: "App")
        }

        // Pre-download Whisper model on first launch if not already cached
        Task {
            if !ModelManager.modelLikelyCached() {
                _ = try? await recorder.transcriptionManager.modelManager.ensureEngine(
                    for: recorder.transcriptionManager.selectedModel
                )
            }
        }

        // The filesystem is the transcription queue: pick up sessions that
        // finished recording but never got a transcript (quit or crash
        // mid-job) — but only if the user wants automatic transcription.
        if recorder.autoTranscribe && recorder.transcriptionMode == .postRecording {
            recorder.transcriptionManager.resumePendingSessions(in: recorder.saveDirectory)
        }
    }
}
