import Foundation
import os

/// Shared logging. The subsystem is set once by whichever app links the
/// package, so entries land under that product's name in Console.
public enum Log {
    public static var subsystem = "com.powercore" {
        didSet { logger = Logger(subsystem: subsystem, category: "core") }
    }
    public static var verbose = false

    private static var logger = Logger(subsystem: subsystem, category: "core")

    public static func info(_ message: String)  { logger.info("\(message, privacy: .public)") }
    public static func error(_ message: String) { logger.error("\(message, privacy: .public)") }

    public static func diag(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if verbose { print(message) }
    }
}
