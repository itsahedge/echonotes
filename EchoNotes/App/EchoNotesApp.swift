import SwiftUI
import AppKit

@main
struct EchoNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Bumped after the system wakes from sleep to force a fresh SwiftUI view
    /// hierarchy. macOS 26 SwiftUI/AttributeGraph state can become stale across
    /// long sleep cycles, causing EXC_BAD_ACCESS in MainActor.assumeIsolated
    /// when the first Button is tapped after wake. Remounting clears that state.
    /// Owned-state classes (RecordingEngine, TranscriptionManager, etc.) live on
    /// AppDelegate, so the rebuild only resets view-local @State.
    @State private var contentID = UUID()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appDelegate.recorder)
                .environment(appDelegate.recorder.transcriptionManager)
                .environment(appDelegate.recorder.transcriptionManager.modelManager)
                .environment(appDelegate.library)
                .id(contentID)
                .onReceive(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                ) { _ in
                    contentID = UUID()
                }
        }
        .defaultSize(width: 960, height: 640)
    }
}
