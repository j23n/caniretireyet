import Foundation
#if canImport(os)
import os
#endif

/// The log of finding, downloading and opening the library, for when it
/// won't open: in Console, filter on the app's bundle identifier
/// (subsystem) and the category `library`.
///
/// Messages hold counts, steps, paths relative to the library folder and
/// error descriptions, never amounts, and are public so Console shows them.
/// `notice` and `error` are kept on the device; `info` shows only while
/// Console streams with info messages on. On Linux nothing is logged.
public enum LibraryLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CanIRetireYet", category: "library")
    #endif

    /// A detail, e.g. a download's progress.
    public static func info(_ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        logger.info("\(text, privacy: .public)")
        #endif
    }

    /// A step, e.g. "found the library" or "downloads finished".
    public static func notice(_ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        logger.notice("\(text, privacy: .public)")
        #endif
    }

    /// Something that went wrong.
    public static func error(_ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        logger.error("\(text, privacy: .public)")
        #endif
    }

    /// A duration in seconds with one decimal, e.g. "2.4 s".
    public static func seconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return "\((seconds * 10).rounded() / 10) s"
    }
}
