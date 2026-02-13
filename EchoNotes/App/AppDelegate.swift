import AppKit
import SwiftUI

/// Manages the menu bar status item and popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?

    let recorder = RecordingEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "EchoNotes")
        button.action = #selector(togglePopover)
        button.target = self
    }

    func updateStatusIcon(isRecording: Bool) {
        let name = isRecording ? "waveform.circle.fill" : "waveform"
        statusItem.button?.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: isRecording ? "EchoNotes (Recording)" : "EchoNotes"
        )
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 280)
        popover.behavior = .transient
        let view = MenuBarView(recorder: recorder, delegate: self)
        popover.contentViewController = NSHostingController(rootView: view)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
