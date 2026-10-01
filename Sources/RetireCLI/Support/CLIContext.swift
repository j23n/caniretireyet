#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import Model
import Prices

/// Where a command writes: normal output to standard output, errors and
/// warnings to standard error. Tests capture both with ``capturing(terminal:)``.
///
/// A long command can show a one-line status on standard error while it
/// works (``status(_:)``), only when that's a terminal: piped, redirected
/// or captured, nothing is shown.
public struct Console: Sendable {
    private let writeOutput: @Sendable (String) -> Void
    private let writeError: @Sendable (String) -> Void
    private let writeStatus: (@Sendable (String) -> Void)?

    /// `status`, when given, writes to a terminal: the status line uses
    /// carriage returns and erases to the end of the line.
    public init(output: @escaping @Sendable (String) -> Void, error: @escaping @Sendable (String) -> Void,
                status: (@Sendable (String) -> Void)? = nil) {
        writeOutput = output
        writeError = error
        writeStatus = status
    }

    /// Whether ``status(_:)`` shows anything: standard error is a terminal.
    public var showsStatus: Bool { writeStatus != nil }

    /// Shows `line` as the status line on standard error, in place of the
    /// one before. Nothing when standard error isn't a terminal.
    public func status(_ line: String) {
        writeStatus?("\r" + line + "\u{1B}[K")
    }

    /// Erases the status line, before the command's output.
    public func clearStatus() {
        writeStatus?("\r\u{1B}[K")
    }

    /// Writes a line to standard output.
    public func print(_ line: String = "") {
        writeOutput(line + "\n")
    }

    /// Writes lines to standard output.
    public func print(lines: [String]) {
        for line in lines { print(line) }
    }

    /// Writes a line to standard error.
    public func error(_ line: String) {
        writeError(line + "\n")
    }

    /// The process's standard output and standard error, with a status line
    /// when standard error is a terminal.
    public static let standard = Console(
        output: { FileHandle.standardOutput.write(Data($0.utf8)) },
        error: { FileHandle.standardError.write(Data($0.utf8)) },
        status: terminalStatus())

    /// Writes status lines to standard error when it's a terminal.
    private static func terminalStatus() -> (@Sendable (String) -> Void)? {
        guard isatty(STDERR_FILENO) == 1 else { return nil }
        return { FileHandle.standardError.write(Data($0.utf8)) }
    }

    /// A console that keeps what is written, for tests. With `terminal`, it
    /// acts as if standard error were a terminal: status lines are kept with
    /// the errors.
    public static func capturing(terminal: Bool = false) -> (Console, CapturedOutput) {
        let captured = CapturedOutput()
        var status: (@Sendable (String) -> Void)?
        if terminal {
            status = { captured.append($0, error: true) }
        }
        return (Console(output: { captured.append($0, error: false) }, error: { captured.append($0, error: true) },
                        status: status),
                captured)
    }
}

/// What was written to a capturing ``Console``.
public final class CapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var outputText = ""
    private var errorText = ""

    init() {}

    func append(_ text: String, error: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if error { errorText += text } else { outputText += text }
    }

    /// Everything written to standard output.
    public var output: String {
        lock.lock()
        defer { lock.unlock() }
        return outputText
    }

    /// Everything written to standard error.
    public var errors: String {
        lock.lock()
        defer { lock.unlock() }
        return errorText
    }
}

/// Everything a command needs from outside: where to write, the environment,
/// the current directory, today's date and how to reach the price APIs.
/// ``live()`` is the real process; tests pass their own.
public struct CLIContext: Sendable {
    public var console: Console
    /// Environment variables, e.g. `RETIRE_LIBRARY` and `COINGECKO_API_KEY`.
    public var environment: [String: String]
    /// Relative paths are resolved against this folder.
    public var currentDirectory: URL
    /// The default date of `networth` and `prices`.
    public var today: CalendarDate
    /// The time stamps of backups.
    public var now: @Sendable () -> Date
    /// How `prices` reaches the price APIs.
    public var httpClient: any HTTPClient
    /// API keys for the price providers.
    public var credentials: any CredentialsProvider

    public init(
        console: Console, environment: [String: String] = [:],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        today: CalendarDate = .today(), now: @escaping @Sendable () -> Date = { Date() },
        httpClient: any HTTPClient = URLSessionHTTPClient(), credentials: (any CredentialsProvider)? = nil
    ) {
        self.console = console
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.today = today
        self.now = now
        self.httpClient = httpClient
        self.credentials = credentials ?? Self.credentials(from: environment)
    }

    /// The running process: standard output and error, its environment and
    /// current directory, today in the device's time zone, and `URLSession`.
    public static func live() -> CLIContext {
        CLIContext(console: .standard, environment: ProcessInfo.processInfo.environment)
    }

    /// The environment variable naming the default library folder.
    public static let libraryVariable = "RETIRE_LIBRARY"
    /// The environment variable holding an optional CoinGecko demo API key.
    public static let coinGeckoKeyVariable = "COINGECKO_API_KEY"

    /// API keys read from environment variables.
    static func credentials(from environment: [String: String]) -> StaticCredentials {
        StaticCredentials([.coingecko: environment[coinGeckoKeyVariable] ?? ""])
    }

    /// `path` as a file URL, relative to the current directory unless absolute.
    func url(forPath path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return currentDirectory.appendingPathComponent(expanded).standardizedFileURL
    }
}

/// A command failed: the message is printed as `Error: …` and the exit code is 1.
struct CLIError: Error, CustomStringConvertible {
    var description: String

    init(_ message: String) {
        description = message
    }
}
