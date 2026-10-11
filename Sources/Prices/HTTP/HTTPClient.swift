import Foundation

/// A request to a price API: a GET, or a POST when it has a body.
///
/// Requests carry only what identifies a quote: a symbol, currencies and
/// dates, plus an API key header where a provider takes one. Amounts and
/// quantities never leave the device.
public struct HTTPRequest: Hashable, Sendable {
    public var url: URL
    /// Header fields, e.g. an API key or a user agent.
    public var headers: [String: String]
    /// The body of a POST; `nil` for a GET.
    public var body: Data?
    /// How long the request may take in total before it's abandoned.
    public var timeout: Duration

    public init(url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: Duration = .seconds(15)) {
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// "POST" with a body, else "GET".
    public var method: String { body == nil ? "GET" : "POST" }
}

/// An HTTP response: status code, header fields and body.
public struct HTTPResponse: Hashable, Sendable {
    public var statusCode: Int
    /// Header fields, keyed by lowercased name.
    public var headers: [String: String]
    public var body: Data

    /// A response. Header names are lowercased so lookups ignore case.
    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
    }

    /// A response with a UTF-8 text body, e.g. a recorded JSON fixture.
    public init(statusCode: Int, headers: [String: String] = [:], text: String) {
        self.init(statusCode: statusCode, headers: headers, body: Data(text.utf8))
    }

    /// The value of a header field, ignoring the case of its name.
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Sends HTTP requests for the price providers.
///
/// The app and the CLI use ``URLSessionHTTPClient``; tests inject a fake that
/// answers with recorded responses, so the test suite never touches the
/// network.
public protocol HTTPClient: Sendable {
    /// Sends `request` and returns the response, whatever its status. Throws
    /// only when no response arrived (no connection, a TLS failure, a
    /// timeout, cancellation).
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
