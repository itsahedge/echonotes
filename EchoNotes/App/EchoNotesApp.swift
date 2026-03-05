import SwiftUI
import AppKit

@main
struct EchoNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appDelegate.recorder)
                .environmentObject(appDelegate.recorder.transcriptionManager)
                .environmentObject(appDelegate.recorder.transcriptionManager.modelManager)
                .environmentObject(appDelegate.library)
        }
        .defaultSize(width: 960, height: 640)

        Settings {
            DesktopSettingsView()
                .environmentObject(appDelegate.recorder)
                .environmentObject(appDelegate.recorder.transcriptionManager)
                .environmentObject(appDelegate.recorder.transcriptionManager.modelManager)
        }
    }
}
