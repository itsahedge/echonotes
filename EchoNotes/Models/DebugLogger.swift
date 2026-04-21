import Foundation
import os

/// In-app debug log that captures entries for display in the UI.
/// Wraps os.Logger so entries go to both Console.app and the in-app debug console.
@MainActor
@Observable
final class DebugLogger {
    static let shared = DebugLogger()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let level: Level
        let message: String

        enum Level: String {
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
            case debug = "DEBUG"
        }
    }

    private(set) var entries: [Entry] = []

    /// Maximum entries to keep in memory.
    @ObservationIgnored private let maxEntries = 500

    private init() {}

    func log(_ message: String, category: String, level: Entry.Level = .info) {
        let entry = Entry(timestamp: Date(), category: category, level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // Also log to os.Logger
        let logger = Logger(subsystem: "com.echonotes", category: category)
        switch level {
        case .info: logger.info("\(message)")
        case .warning: logger.warning("\(message)")
        case .error: logger.error("\(message)")
        case .debug: logger.debug("\(message)")
        }
    }

    func info(_ message: String, category: String) {
        log(message, category: category, level: .info)
    }

    func warning(_ message: String, category: String) {
        log(message, category: category, level: .warning)
    }

    func error(_ message: String, category: String) {
        log(message, category: category, level: .error)
    }

    func debug(_ message: String, category: String) {
        log(message, category: category, level: .debug)
    }

    func clear() {
        entries.removeAll()
    }
}
