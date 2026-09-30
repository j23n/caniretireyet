import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The default ``HTTPClient``, built on `URLSession`.
///
/// It uses an ephemeral session by default: no cookies, no disk cache and no
/// credentials are kept between requests.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    /// A client using `session`, or a private ephemeral session.
    public init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.timeoutInterval = request.timeout.timeInterval
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

extension Duration {
    /// The duration in seconds, for Foundation APIs.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
