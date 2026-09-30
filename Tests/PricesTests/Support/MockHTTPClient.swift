import Foundation
import Prices

/// A fake ``HTTPClient`` that answers with recorded responses and remembers
/// every request. A route matches when the request URL contains its pattern;
/// the first matching route answers. A route with several responses answers
/// with them in turn and then repeats the last one.
actor MockHTTPClient: HTTPClient {
    struct Route {
        var pattern: String
        var responses: [HTTPResponse]
        /// How long to wait before answering (cancellable).
        var delay: Duration?
        /// Thrown instead of answering.
        var error: (any Error & Sendable)?
    }

    /// A delay no test waits out: a route with it answers only if nothing
    /// times the request out first, which is how tests model a service that
    /// never answers. The wait ends as soon as the request is cancelled.
    static let never: Duration = .seconds(3600)

    private var routes: [Route] = []
    private(set) var requests: [HTTPRequest] = []

    init() {}

    /// A client with routes answering 200 with the given JSON bodies.
    init(_ routes: [String: String]) {
        self.routes = routes.map { Route(pattern: $0.key, responses: [HTTPResponse(statusCode: 200, text: $0.value)]) }
    }

    /// Adds a route answering with `responses` in turn.
    func on(_ pattern: String, _ responses: HTTPResponse..., delay: Duration? = nil) {
        routes.append(Route(pattern: pattern, responses: responses, delay: delay))
    }

    /// Adds a route answering 200 with a JSON body.
    func on(_ pattern: String, json: String, delay: Duration? = nil) {
        routes.append(Route(pattern: pattern, responses: [HTTPResponse(statusCode: 200, text: json)], delay: delay))
    }

    /// Adds a route that fails without a response.
    func on(_ pattern: String, error: any Error & Sendable) {
        routes.append(Route(pattern: pattern, responses: [], error: error))
    }

    /// The requests whose URL contains `pattern`.
    func requests(matching pattern: String) -> [HTTPRequest] {
        requests.filter { $0.url.absoluteString.contains(pattern) }
    }

    var requestCount: Int { requests.count }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        let url = request.url.absoluteString
        guard let index = routes.firstIndex(where: { url.contains($0.pattern) }) else {
            return HTTPResponse(statusCode: 404, text: "No recorded response for \(url)")
        }
        let route = routes[index]
        if let delay = route.delay { try await Task.sleep(for: delay) }
        if let error = route.error { throw error }
        if routes[index].responses.count > 1 { return routes[index].responses.removeFirst() }
        return route.responses[0]
    }
}
