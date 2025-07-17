//
//  ChewingLogger.swift
//  Chewing
//

import Foundation
import libchewing

// MARK: - ChewingLogger

/// Routes log messages emitted by the Chewing engine through a user-configurable `LoggingConfig`.
///
/// The `ChewingLogger` manages registration of a Swift-side logger callback, transforms raw C log
/// messages into Swift `String` instances, applies filtering based on log levels, and forwards
/// messages to either a custom callback or the system `OSLog`.
package struct ChewingLogger {
    /// Actor that maintains the active `ChewingLogger` instance for thread-safe access.
    actor LoggerState {
        static let shared = LoggerState()
        private var current: ChewingLogger?

        /// Registers the provided `ChewingLogger` as the current active logger.
        func register(_ logger: ChewingLogger) {
            current = logger
        }

        /// Retrieves the currently registered `ChewingLogger` instance, if any.
        func getCurrent() -> ChewingLogger? {
            return current
        }
    }

    /// The default `OSLog` logger used when no callback is configured by the user.
    private static let osLogger = Logger(subsystem: "chewing", category: "ChewingLogger")
    /// Serial dispatch queue to serialize `OSLog` calls for thread-safe logging.
    private static let osLoggerQueue = DispatchQueue(label: "chewing.ChewingLogger.osLoggerQueue")

    /// Configuration controlling which log levels are enabled and the custom callback to invoke.
    let config: LoggingConfig

    /// Initializes a new `ChewingLogger` with the specified configuration and registers it as the active logger.
    ///
    /// - Parameter config: The `LoggingConfig` specifying enabled log levels and an optional callback.
    /// - Note: Registration is performed asynchronously on a background task.
    init(config: LoggingConfig) {
        self.config = config
        Task {
            await LoggerState.shared.register(self)
        }
    }

    /// A C-compatible function pointer to receive raw log messages from the Chewing engine.
    ///
    /// This callback is passed to the native engine to handle incoming log data, filters messages
    /// according to the active `LoggingConfig`, duplicates C strings for memory safety, decodes them
    /// into Swift `String`s, and forwards valid messages to the instance `log(level:message:)` method.
    ///
    /// - Parameters:
    ///   - level: The numeric log level constant defined by the Chewing C engine.
    ///   - message: A null-terminated C string containing the log message text.
    static let cLogger: @convention(c) (Int32, UnsafePointer<CChar>?) -> Void = { level, message in
        Task {
            guard let logger = await LoggerState.shared.getCurrent(),
                  logger.config.enabled else { return }

            let logLevel = LogLevel.fromChewing(level: level)
            guard logger.config.levels.contains(logLevel) else { return }

            guard let dup = strdup(message) else { return }
            defer { free(dup) }
            guard let msgStr = String(validatingUTF8: dup) else { return }

            logger.log(level: logLevel, message: "[chewing]\(msgStr)")
        }
    }

    /// Logs the given message at the specified log level.
    ///
    /// If a custom callback is configured in `LoggingConfig`, forwards the message to that callback.
    /// Otherwise, dispatches the message to the system `OSLog` on a serial queue.
    ///
    /// - Parameters:
    ///   - level: The application-level `LogLevel` for this message.
    ///   - message: The formatted log message text.
    func log(level: LogLevel, message: String) {
        if let cb = config.callback {
            cb(level, message)
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
