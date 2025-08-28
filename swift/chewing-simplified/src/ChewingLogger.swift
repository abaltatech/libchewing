//
//  ChewingLogger.swift
//  Chewing
//

import Foundation
import libchewing
import os

// MARK: - ChewingLogger

/// Manages routing of raw log messages from the Chewing C engine to Swift logging backends.
///
/// Transforms C log callbacks into Swift `String` instances, filters entries according to
/// `LoggingConfig`, and forwards them to a user-provided callback or the system `OSLog`.
@frozen package struct ChewingLogger {
    /// The default `OSLog` logger used when no callback is configured by the user.
    private static let osLogger = Logger(subsystem: "chewing", category: "ChewingLogger")
    /// Serial dispatch queue to serialize `OSLog` calls for thread-safe logging.
    private static let osLoggerQueue = DispatchQueue(label: "chewing.ChewingLogger.osLoggerQueue")
    /// Backing storage for the active `ChewingLogger` instance.
    private static var current: ChewingLogger?

    /// Thread-safe accessor for the currently registered `ChewingLogger` instance.
    /// - Note: Uses `osLoggerQueue` to synchronize reads and writes.
    private static var shared: ChewingLogger? {
        get {
            ChewingLogger.osLoggerQueue.sync { ChewingLogger.current }
        }
        set {
            ChewingLogger.osLoggerQueue.async { ChewingLogger.current = newValue }
        }
    }

    /// Configuration controlling which log levels are enabled and the custom callback to invoke.
    let config: LoggingConfig

    /// Initializes a new `ChewingLogger` with the specified configuration and registers it as the active logger.
    ///
    /// - Parameter config: The `LoggingConfig` specifying enabled log levels and an optional callback.
    /// - Note: Registration is performed asynchronously on a background task.
    init(config: LoggingConfig) {
        self.config = config
        ChewingLogger.shared = self
    }

    /// C-compatible log handler used by the Chewing C engine to forward log messages to Swift.
    ///
    /// Passed to the native engine as the log callback, this closure filters and transforms raw C
    /// log messages into Swift `String` instances and dispatches them via the active `ChewingLogger`.
    ///
    /// - Parameters:
    ///   - level: The numeric log level constant defined by the Chewing C engine.
    ///   - message: A null-terminated C string containing the log message text.
    static let cLogger: @convention(c) (Int32, UnsafePointer<CChar>?) -> Void = { level, message in
        guard let logger = ChewingLogger.shared, logger.config.enabled else { return }

        let logLevel = LogLevel.fromChewing(level: level)
        guard logger.config.levels.contains(logLevel) else { return }

        guard let dup = strdup(message) else { return }
        defer { free(dup) }
        guard let msgStr = String(validatingUTF8: dup) else { return }

        logger.log(level: logLevel, message: "[chewing]\(msgStr)")
    }

    /// Logs a message at the specified level, using either a custom callback or `OSLog`.
    ///
    /// Depending on the `LoggingConfig`, forwards the log entry to the user callback or
    /// asynchronously emits it via the system `OSLog` on the `osLoggerQueue`.
    ///
    /// - Parameters:
    ///   - level: The severity level of the log message.
    ///   - message: The content of the log entry.
    func log(level: LogLevel, message: String) {
        if let callback = config.callback {
            callback(level, message)
        } else {
            ChewingLogger.osLoggerQueue.async {
                switch level {
                case .critical:
                    ChewingLogger.osLogger.critical("\(message)")
                case .error:
                    ChewingLogger.osLogger.error("\(message)")
                case .warning:
                    ChewingLogger.osLogger.warning("\(message)")
                case .info:
                    ChewingLogger.osLogger.info("\(message)")
                case .debug:
                    ChewingLogger.osLogger.debug("\(message)")
                case .verbose:
                    ChewingLogger.osLogger.trace("\(message)")
                default:
                    ChewingLogger.osLogger.notice("Unknown log level: \(level), \(message)")
                }
            }
        }
    }
}

// MARK: - LogLevel

private extension LogLevel {
    /// Converts a numeric log level from the Chewing C engine into the Swift `LogLevel` enum.
    ///
    /// - Parameter level: The integer log level value from the native Chewing engine.
    /// - Returns: The corresponding `LogLevel` value, or an empty set for unknown levels.
    static func fromChewing(level: Int32) -> LogLevel {
        switch level {
        case CHEWING_LOG_ERROR: return .error
        case CHEWING_LOG_WARN: return .warning
        case CHEWING_LOG_INFO: return .info
        case CHEWING_LOG_DEBUG: return .debug
        case CHEWING_LOG_VERBOSE: return .verbose
        default: return []
        }
    }
}
