/// A problem in one file of the library: found reading the file, or
/// checking it against the rest of the library (`Library.problems()` in
/// Tracker). The library loads and works regardless.
public struct LibraryIssue: Hashable, Sendable, CustomStringConvertible {
    /// How much of the file was affected.
    public enum Severity: String, Hashable, Sendable {
        /// The file, or some records in it, couldn't be loaded.
        case error
        /// Everything was loaded, but something should be fixed.
        case warning
    }

    /// The file's path relative to the library folder.
    public var path: String
    /// What is wrong, and where in the file, in plain words.
    public var message: String
    public var severity: Severity

    public init(path: String, message: String, severity: Severity) {
        self.path = path
        self.message = message
        self.severity = severity
    }

    /// `path: message`
    public var description: String { "\(path): \(message)" }
}

extension Sequence<LibraryIssue> {
    /// The issues by path, errors before warnings, each in the order found.
    public func sortedByPath() -> [LibraryIssue] {
        enumerated().sorted { lhs, rhs in
            (lhs.element.path, lhs.element.severity == .error ? 0 : 1, lhs.offset)
                < (rhs.element.path, rhs.element.severity == .error ? 0 : 1, rhs.offset)
        }.map(\.element)
    }
}
