import Foundation
import os

enum Log {
    private static let logger = Logger(subsystem: "com.gazefocus.app", category: "core")

    static func info(_ message: String)  { logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)") }

    /// Mirrored to stdout so `--diagnose` runs are readable without Console.app.
    static func diag(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if Prefs.shared.verbose { print(message) }
    }
}
