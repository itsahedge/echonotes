import SwiftUI
import AppKit

@main
struct EchoNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appDelegate.recorder)
                .environment(appDelegate.recorder.transcriptionManager)
                .environment(appDelegate.recorder.transcriptionManager.modelManager)
                .environment(appDelegate.library)
        }
        .defaultSize(width: 960, height: 640)
    }
}
