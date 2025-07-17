//
//  ChewingWrapper.swift
//  Chewing
//

import Darwin
import Foundation
import libchewing

// MARK: - ChewingWrapperError

/// Errors that can occur when initializing or using the ChewingWrapper.
public enum ChewingWrapperError: Error {
    /// Indicates that the Chewing data directory could not be located.
    case notFound
    /// Indicates that initialization of the native Chewing engine failed.
    case initializationFailed
    /// Indicates that `configure(_:)` was not called before accessing the singleton.
    case notConfigured
}

// MARK: - ChewingWrapper

/// A Swift wrapper around the native Chewing C API (libchewing).
///
/// This actor manages the lifecycle of the Chewing input context,
/// forwards keystrokes to the library, and dispatches callback events
/// (buffer updates, candidate lists, commits, and logging) to Swift closures.
///
/// Callback closures (`onCandidateUpdate`, `onCommit`, `onBufferUpdate`, `onPreeditUpdate`) are invoked within the actor's executor context; consumers are responsible for dispatching to the main thread for UI updates.
///
/// This wrapper is a singleton and must be configured exactly once before use by calling
/// `ChewingWrapper.configure(_:)`. Access the shared instance via `ChewingWrapper.shared()`.
/// - Note: Call `ChewingWrapper.reset()` to tear down and reconfigure for a new instance.
public actor ChewingWrapper {
    /// Configuration options for initializing the singleton ChewingWrapper.
    /// Customize candidate page size, symbol length, and data paths prior to first use.
    public struct Configuration {
        public var candPerPage: Int
        public var maxChiSymbolLen: Int
        public var dataDirectoryPath: String?
        public var userDirectoryPath: String?
        public var loggingConfig: LoggingConfig

        /// Creates a new Configuration for the ChewingWrapper singleton.
        /// - Parameters:
        ///   - candPerPage: Number of candidate words per page.
        ///   - maxChiSymbolLen: Maximum Chinese symbol length.
        ///   - dataDirectoryPath: Optional override for the data directory path.
        ///   - userDirectoryPath: Optional override for the user directory path.
        ///   - loggingConfig: Logging configuration.
        public init(
            candPerPage: Int = 10,
            maxChiSymbolLen: Int = 18,
            dataDirectoryPath: String? = nil,
            userDirectoryPath: String? = nil,
            loggingConfig: LoggingConfig
        ) {
            self.candPerPage = candPerPage
            self.maxChiSymbolLen = maxChiSymbolLen
            self.dataDirectoryPath = dataDirectoryPath
            self.userDirectoryPath = userDirectoryPath
            self.loggingConfig = loggingConfig
        }
    }

    /// Pre-configuration used to initialize the shared instance.
    private static var preconfigured: Configuration?

    /// Pre-configures the ChewingWrapper singleton.
    /// Must be called exactly once before first accessing `ChewingWrapper.shared()`.
    /// - Parameter config: The configuration to use for the shared instance.
    public static func configure(_ config: Configuration) {
        preconfigured = config
    }

    /// Cached shared instance after successful initialization.
    private static var sharedInstance: ChewingWrapper?

    /// Returns the singleton `ChewingWrapper` instance, initializing it if needed.
    ///
    /// If the wrapper has not been preconfigured via `configure(_:)`, this method throws the corresponding error.
    ///
    /// - Returns: The shared `ChewingWrapper` instance.
    /// - Throws:
    ///   - `ChewingWrapperError.notConfigured` if `configure(_:)` was not called.
    ///   - `ChewingWrapperError.initializationFailed` if the underlying native engine initialization fails.
    public static func shared() throws -> ChewingWrapper {
        if let inst = sharedInstance {
            return inst
        }
        guard let cfg = preconfigured else {
            throw ChewingWrapperError.notConfigured
        }
        let wrapper = try ChewingWrapper(cfg: cfg)
        sharedInstance = wrapper
        return wrapper
    }

    /// Resets the `ChewingWrapper` singleton, allowing a new configuration.
    ///
    /// Deallocates the current instance and clears any preconfigured settings.
    /// After calling this, `configure(_:)` must be invoked before accessing `shared()`.
    public static func reset() {
        sharedInstance = nil
        preconfigured = nil
    }

    /// Initializes a new `ChewingWrapper` instance with the specified configuration.
    ///
    /// - Parameter cfg: The configuration options used to set up the Chewing engine.
    /// - Throws:
    ///   - `ChewingWrapperError.notFound` if the data directory path cannot be located.
    ///   - `ChewingWrapperError.initializationFailed` if allocation of C strings or engine initialization fails.
    private init(cfg: Configuration) throws {
        // Initialize the internal logger to route Chewing logs
        logger = ChewingLogger(config: cfg.loggingConfig)

        guard let dataDirectoryPath = cfg.dataDirectoryPath ?? ChewingWrapper.dataDirectoryPath else {
            logger.log(level: .critical, message: "Failed to retrieve data directory path")
            throw ChewingWrapperError.notFound
        }

        let userDirectoryPath = cfg.userDirectoryPath ?? dataDirectoryPath

        guard let dataCString = strdup(dataDirectoryPath),
              let userCString = strdup(userDirectoryPath)
        else {
            logger.log(level: .critical, message: "Failed to allocate C strings for data directory paths")
            throw ChewingWrapperError.initializationFailed
        }
        defer {
            free(dataCString)
            free(userCString)
        }

        var config = cs_config_t(
            data_path: dataCString,
            user_path: userCString,
            cand_per_page: Int32(cfg.candPerPage),
            max_chi_symbol_len: Int32(cfg.maxChiSymbolLen)
        )
        let callbacks = cs_callbacks_s(
            candidate_info: ChewingWrapper.candidateInfoHandler,
            buffer: ChewingWrapper.bufferHandler,
            bopomofo: ChewingWrapper.preeditHandler,
            commit: ChewingWrapper.commitHandler,
            logger: ChewingLogger.cLogger
        )
        ctx = cs_context_s(config: config, callbacks: callbacks)
        isInitialized = cs_init(&ctx)
        if !isInitialized {
            logger.log(level: .critical, message: "Failed to initialize Chewing")
            throw ChewingWrapperError.initializationFailed
        }
    }

    deinit {
        guard isInitialized else { return }
        _ = cs_terminate()
        ctx = cs_context_s()
        isInitialized = false
    }

    /// These are Swift closures that user code can set:
    /// Closure invoked when the Chewing engine generates a new list of candidates.
    /// - Parameter candidates: An array of candidate strings from the engine.
    /// - Note: Invoked within the actor's context; consumers must dispatch to the main thread for UI updates.
    public var onCandidateUpdate: (([String]) -> Void)?
    /// Closure invoked when the Chewing engine commits text to the application.
    /// - Parameter committedText: The string that was committed.
    /// - Note: Invoked within the actor's context; consumers must dispatch to the main thread for UI updates.
    public var onCommit: ((String) -> Void)?
    /// Closure invoked when the Chewing engine's composed buffer is updated.
    /// - Parameter bufferText: The current content of the composition buffer.
    /// - Note: Invoked within the actor's context; consumers must dispatch to the main thread for UI updates.
    public var onBufferUpdate: ((String) -> Void)?
    /// Closure invoked when the Chewing engine's preedit (in-progress composition) text changes.
    /// - Parameter preeditText: The current preedit text.
    /// - Note: Invoked within the actor's context; consumers must dispatch to the main thread for UI updates.
    public var onPreeditUpdate: ((String) -> Void)?

    /// Returns the file system path to the directory containing Chewing data files.
    ///
    /// The Chewing package should include required `.dat` resources under
    /// its SwiftPM `resources:` configuration. This path is used when
    /// initializing the Chewing context.
    public static var dataDirectoryPath: String? {
        return Bundle.module.resourcePath
    }

    private var ctx: cs_context_s = .init()
    private var isInitialized: Bool = false
    private var logger: ChewingLogger
}

// MARK: - Interacting with libchewing

public extension ChewingWrapper {
    /// Processes a single character input through the Chewing engine.
    ///
    /// This method serializes execution within the actor's context.
    ///
    /// - Parameter key: A character representing a keystroke (e.g., letter, space, backspace, or enter).
    /// - Returns: `true` if the engine processed the key successfully; otherwise, `false`.
    @discardableResult
    func process(key: Character) -> Bool {
        guard isInitialized else { return false }
        guard let cKey = key.asciiValue else { return false }

        return cs_process_key(CChar(cKey))
    }

    /// Processes a special key input through the Chewing engine.
    ///
    /// - Parameter key: A `ChewingKey` value (e.g., `.enter`, `.space`, `.backspace`).
    /// - Returns: `true` if the engine processed the key successfully; otherwise, `false`.
    @discardableResult
    func process(key: ChewingKey) -> Bool {
        guard isInitialized else { return false }

        return cs_process_key(key.cValue)
    }

    /// Selects a candidate option by its index.
    ///
    /// - Parameter index: Zero-based index of the candidate to commit.
    /// - Returns: `true` if selection succeeded; otherwise, `false`.
    @discardableResult
    func selectCandidate(at index: Int) -> Bool {
        guard isInitialized else { return false }

        return cs_select_candidate(Int32(index))
    }
}

// MARK: - Callback Registration

public extension ChewingWrapper {
    /// Registers closures to receive events from the Chewing engine.
    ///
    /// This method is actor-isolated and must be called with `await`.
    ///
    /// - Parameters:
    ///   - onCandidateUpdate: Called with an array of candidate strings when the candidate list updates.
    ///   - onBufferUpdate: Called with the current buffer text when it changes.
    ///   - onPreeditUpdate: Called with the current preedit text when it changes.
    ///   - onCommit: Called with the committed text when the engine commits input.
    func registerCallbacks(
        onCandidateUpdate: @escaping ([String]) -> Void,
        onBufferUpdate: @escaping (String) -> Void,
        onPreeditUpdate: @escaping (String) -> Void,
        onCommit: @escaping (String) -> Void
    ) {
        self.onCandidateUpdate = onCandidateUpdate
        self.onBufferUpdate = onBufferUpdate
        self.onPreeditUpdate = onPreeditUpdate
        self.onCommit = onCommit
    }
}

// MARK: - C callback entry points (bridge to instance closures)

private extension ChewingWrapper {
    /// C callback invoked when the Chewing engine has generated a list of candidates.
    ///
    /// - Parameters:
    ///   - pageSize: Number of candidates per page (unused).
    ///   - numPages: Total number of pages (unused).
    ///   - candOnPage: Index of the current page (unused).
    ///   - total: Total number of candidates available.
    ///   - items: C array of C strings representing candidate words.
    private static let candidateInfoHandler: @convention(c) (Int32, Int32, Int32, Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Void = { _, _, _, total, items in
        guard let wrapper = try? ChewingWrapper.shared() else { return }
        guard let items else { return }

        let buffer = UnsafeBufferPointer(start: items, count: Int(total))
        let candidates = buffer.compactMap { ptr -> String? in
            guard let cStrPtr = ptr else { return nil }
            return String(cString: cStrPtr, encoding: .utf8)
        }

        guard !candidates.isEmpty else { return }
        Task { await wrapper.handleCandidateUpdate(candidates) }
    }

    /// C callback invoked when the Chewing engine's buffer (composed text) is updated.
    ///
    /// - Parameter buf: C string containing the current buffer content.
    private static let bufferHandler: @convention(c) (UnsafePointer<CChar>?) -> Void = { buf in
        guard let wrapper = try? ChewingWrapper.shared() else { return }
        guard let buf, let str = String(cString: buf, encoding: .utf8) else { return }
        Task { await wrapper.handleBufferUpdate(str) }
    }

    /// C callback invoked when the Chewing engine's preedit (in-progress composition) is updated.
    ///
    /// - Parameter buf: C string containing the current preedit text.
    private static let preeditHandler: @convention(c) (UnsafePointer<CChar>?) -> Void = { buf in
        guard let wrapper = try? ChewingWrapper.shared() else { return }
        guard let buf, let str = String(cString: buf, encoding: .utf8) else { return }
        Task { await wrapper.handlePreeditUpdate(str) }
    }

    /// C callback invoked when the Chewing engine commits text to the application.
    ///
    /// - Parameter buf: C string containing the committed text.
    private static let commitHandler: @convention(c) (UnsafePointer<CChar>?) -> Void = { buf in
        guard let wrapper = try? ChewingWrapper.shared() else { return }
        guard let buf, let str = String(cString: buf, encoding: .utf8) else { return }
        Task { await wrapper.handleCommit(str) }
    }

    // MARK: - Callback routing handlers (actor methods)

    private func handleCandidateUpdate(_ candidates: [String]) {
        onCandidateUpdate?(candidates)
    }

    private func handleBufferUpdate(_ bufferText: String) {
        onBufferUpdate?(bufferText)
    }

    private func handlePreeditUpdate(_ preeditText: String) {
        onPreeditUpdate?(preeditText)
    }

    private func handleCommit(_ committedText: String) {
        onCommit?(committedText)
    }
}
