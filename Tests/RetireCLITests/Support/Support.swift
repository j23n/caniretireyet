import Foundation
import Model
import Prices
import RetireCLI
import Storage
import TestSupport

/// What one run of `retire` printed and returned.
struct CLIRun {
    var status: Int32
    var output: String
    var errors: String

    /// Output and errors together, for messages.
    var all: String { output + errors }
}

/// Runs `retire` with `arguments` in a test context: output is captured,
/// today is 2026-09-30 (the example library's last check-in), and the price
/// APIs are answered by `client` (by default, every request fails).
func retire(_ arguments: [String], environment: [String: String] = [:], currentDirectory: URL? = nil,
            today: CalendarDate = "2026-09-30", client: (any HTTPClient)? = nil,
            clock: TestClock = TestClock()) async -> CLIRun {
    let (console, captured) = Console.capturing()
    let context = CLIContext(
        console: console, environment: environment,
        currentDirectory: currentDirectory ?? FileManager.default.temporaryDirectory, today: today,
        now: { clock.next() }, httpClient: client ?? MockHTTPClient(), credentials: StaticCredentials())
    let status = await RetireCLI.run(arguments, context: context)
    return CLIRun(status: status, output: captured.output, errors: captured.errors)
}

/// A clock for backup time stamps that moves one second per reading, so
/// backups sort in the order they were taken.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 1_790_762_400)) {
        current = start
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(1)
        return current
    }
}

/// A temporary folder for one test, deleted when the value goes away.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetireCLITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// A temporary copy of the example library.
    static func exampleLibrary() throws -> TemporaryFolder {
        let folder = try TemporaryFolder()
        for path in Fixtures.allJSONFiles {
            try folder.write(path, Fixtures.data(for: path))
        }
        return folder
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var path: String { url.path }

    var library: LibraryFolder { LibraryFolder(root: url) }

    func url(_ path: String) -> URL {
        url.appendingPathComponent(path)
    }

    func write(_ path: String, _ data: Data) throws {
        let fileURL = url(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func write(_ path: String, _ text: String) throws {
        try write(path, Data(text.utf8))
    }

    func text(_ path: String) throws -> String {
        String(decoding: try Data(contentsOf: url(path)), as: UTF8.self)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    /// Every file, relative and sorted, except those in `backups/`.
    func dataFiles() throws -> [String] {
        try LocalFileAccess().listFiles(in: url).filter { !$0.hasPrefix("backups/") }
    }

    /// The contents of every file except backups, to compare states.
    func snapshot() throws -> [String: Data] {
        var files: [String: Data] = [:]
        for path in try dataFiles() { files[path] = try Data(contentsOf: url(path)) }
        return files
    }

    /// The backup folders, oldest first.
    func backups() throws -> [Backup] {
        try library.backups()
    }

    /// Loads the library with Storage.
    func load() throws -> Library {
        try library.load().library
    }
}

/// A decimal from a string, exactly.
func dec(_ string: String) -> Decimal {
    Decimal(fileString: string)!
}

/// Parses JSON output into dictionaries and arrays.
func parseJSON(_ text: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
    guard let dictionary = object as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
    return dictionary
}

/// A fake `HTTPClient` that answers from recorded responses and remembers
/// every request. A route matches when the request URL contains its pattern;
/// anything else gets a 404.
actor MockHTTPClient: HTTPClient {
    private var routes: [(pattern: String, response: HTTPResponse)] = []
    private(set) var requests: [HTTPRequest] = []

    /// A client with routes answering 200 with the given JSON bodies.
    init(_ routes: [String: String] = [:]) {
        self.routes = routes.sorted { $0.key < $1.key }.map { ($0.key, HTTPResponse(statusCode: 200, text: $0.value)) }
    }

    /// Answers requests matching `pattern` with `response`, before the other routes.
    func on(_ pattern: String, _ response: HTTPResponse) {
        routes.insert((pattern, response), at: 0)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        let url = request.url.absoluteString
        return routes.first { url.contains($0.pattern) }?.response
            ?? HTTPResponse(statusCode: 404, text: "No recorded response for \(url)")
    }
}
