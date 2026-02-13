import SwiftUI
import AppKit

@main
struct EchoNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar-only app — no main window, no settings scene
        Settings { EmptyView() }
    }
}
