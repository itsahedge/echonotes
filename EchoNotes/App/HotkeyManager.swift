import Carbon
import AppKit
import os

/// Manages a global keyboard shortcut (⌘⇧R) to toggle recording.
/// Uses Carbon's RegisterEventHotKey API — no external dependencies.
@MainActor
final class HotkeyManager {
    private let logger = Logger(subsystem: "com.echonotes", category: "HotkeyManager")
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onToggle: (() -> Void)?

    /// The shared instance used by the Carbon callback to route events.
    fileprivate static var shared: HotkeyManager?

    deinit {
        // Safety net — ensure cleanup even if unregister() wasn't called explicitly
        if hotkeyRef != nil || eventHandler != nil {
            unregister()
        }
    }

    /// Register the global hotkey. Call once at app launch.
    func register(onToggle: @escaping () -> Void) {
        if HotkeyManager.shared != nil {
            logger.warning("Overwriting existing HotkeyManager.shared — was unregister() missed?")
        }
        self.onToggle = onToggle
        HotkeyManager.shared = self

        // ⌘⇧R: keycode 15 = 'R', modifiers = cmdKey + shiftKey
        let hotkeyID = EventHotKeyID(signature: fourCharCode("ECHO"), id: 1)
        var hotkey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(cmdKey | shiftKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkey
        )

        guard status == noErr else {
            logger.error("Failed to register hotkey: \(status)")
            return
        }
        hotkeyRef = hotkey

        // Install Carbon event handler for hotkey events
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handler: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &eventType,
            nil,
            &handler
        )
        eventHandler = handler
        logger.info("Global hotkey ⌘⇧R registered")
    }

    /// Unregister the hotkey. Call on app quit.
    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        HotkeyManager.shared = nil
        logger.info("Global hotkey unregistered")
    }

    fileprivate func handleHotkeyPress() {
        onToggle?()
    }

    func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}

/// Carbon callback — must be a free function. Routes to the shared HotkeyManager.
private func hotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    Task { @MainActor in
        HotkeyManager.shared?.handleHotkeyPress()
    }
    return noErr
}
