import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends a provider's requests: applies the per-request deadline and the
/// rate-limit retries of a ``RequestPolicy``, and turns transport failures
/// into ``PriceFetchError``s that name the service.
struct HTTPFetcher: Sendable {
    let client: any HTTPClient
    let policy: RequestPolicy
    /// The service's display name, for error messages.
    let service: String

    /// GETs `url` and returns the response, whatever its status, except that
    /// a 429 is retried per the policy and then thrown as `rateLimited`.
    func get(_ url: URL, headers: [String: String] = [:]) async throws(PriceFetchError) -> HTTPResponse {
        let request = HTTPRequest(url: url, headers: headers, timeout: policy.timeout)
        var attempt = 0
        while true {
            let response = try await sendOnce(request)
            let hint = response.retryAfter
            let isRateLimited = response.statusCode == 429 || (response.statusCode == 503 && hint != nil)
            guard isRateLimited else { return response }
            let wait = hint ?? policy.retryWaitWithoutHint
            guard attempt < policy.maxRetries, wait <= policy.maxRetryWait else {
                throw .rateLimited(service: service, retryAfter: hint)
            }
            attempt += 1
            do {
                try await Task.sleep(for: wait)
            } catch {
                throw .cancelled
            }
        }
    }

    private func sendOnce(_ request: HTTPRequest) async throws(PriceFetchError) -> HTTPResponse {
        let client = self.client
        do {
            return try await withDeadline(request.timeout) { try await client.send(request) }
        } catch let error as PriceFetchError {
            throw error
        } catch is DeadlineExceeded {
            throw .timedOut(service: service, after: request.timeout)
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw .timedOut(service: service, after: request.timeout)
            case .cancelled: throw .cancelled
            default: throw .network(service: service, message: Self.describe(error))
            }
        } catch {
            throw .network(service: service, message: String(describing: error))
        }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: "the device is offline"
        case .cannotFindHost, .dnsLookupFailed: "the server's name couldn't be resolved"
        case .cannotConnectToHost: "the server refused the connection"
        case .networkConnectionLost: "the connection was lost"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            "a secure connection couldn't be made"
        default: "network error \(error.code.rawValue)"
        }
    }
}

/// Thrown by ``withDeadline(_:_:)`` when the operation takes too long.
struct DeadlineExceeded: Error {}

/// Runs `operation`, cancelling it and throwing ``DeadlineExceeded`` if it
/// hasn't finished within `timeout`.
func withDeadline<T: Sendable>(
    _ timeout: Duration, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            return nil
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw CancellationError() }
        guard let value = first else { throw DeadlineExceeded() }
        return value
    }
}

// MARK: - Reading responses

extension HTTPResponse {
    /// `Retry-After` in seconds, if the response has one.
    var retryAfter: Duration? {
        guard let value = header("Retry-After")?.trimmingCharacters(in: .whitespaces),
              let seconds = Int(value), seconds >= 0
        else { return nil }
        return .seconds(seconds)
    }

    /// Throws the ``PriceFetchError`` for an unsuccessful status: 401 and 403
    /// are `unauthorized`, 404 is `unknownSymbol`, 429 is `rateLimited`.
    func requireSuccess(service: String, symbol: String) throws(PriceFetchError) {
        switch statusCode {
        case 200..<300: return
        case 401, 403: throw .unauthorized(service: service, message: errorMessage)
        case 404: throw .unknownSymbol(service: service, symbol: symbol, message: errorMessage)
        case 429: throw .rateLimited(service: service, retryAfter: retryAfter)
        default: throw .httpStatus(service: service, code: statusCode, message: errorMessage)
        }
    }

    /// Decodes a JSON body, or throws `malformedResponse` saying what was wrong.
    func decodeJSON<T: Decodable>(_ type: T.Type, service: String) throws(PriceFetchError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: body)
        } catch let error as DecodingError {
            throw .malformedResponse(service: service, detail: Self.describe(error))
        } catch {
            throw .malformedResponse(service: service, detail: "not JSON")
        }
    }

    /// A readable error message from the body: the first message-like field
    /// of a JSON body (`description`, `error_message`, `message`, `label`,
    /// `detail`, `error`), or a short plain-text body.
    var errorMessage: String? {
        if let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
            return Self.findMessage(in: object, depth: 0).map(Self.shorten)
        }
        guard let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("<")
        else { return nil }
        return Self.shorten(text)
    }

    private static let messageKeys = ["description", "error_message", "message", "label", "detail", "error"]

    private static func findMessage(in value: Any, depth: Int) -> String? {
        guard depth < 5 else { return nil }
        if let dictionary = value as? [String: Any] {
            for key in messageKeys {
                if let string = dictionary[key] as? String, !string.isEmpty { return string }
            }
            for key in dictionary.keys.sorted() {
                if let found = findMessage(in: dictionary[key]!, depth: depth + 1) { return found }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = findMessage(in: element, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    private static func shorten(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 200 ? String(line.prefix(200)) + "…" : line
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context, _ key: CodingKey? = nil) -> String {
            let keys = context.codingPath + (key.map { [$0] } ?? [])
            let parts = keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }
            let joined = parts.joined()
            return joined.hasPrefix(".") ? String(joined.dropFirst()) : joined
        }
        switch error {
        case .keyNotFound(let key, let context): return "missing \(path(context, key))"
        case .valueNotFound(_, let context): return "missing value at \(path(context))"
        case .typeMismatch(_, let context): return "unexpected value at \(path(context))"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty ? "not JSON" : "unreadable value at \(path(context))"
        @unknown default: return "unreadable"
        }
    }
}
