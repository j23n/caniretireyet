/// How providers send requests: the per-request timeout, and how to react
/// when a service asks to slow down (HTTP 429, or 503 with `Retry-After`).
public struct RequestPolicy: Hashable, Sendable {
    /// How long one request may take before it's abandoned.
    public var timeout: Duration
    /// How many times a rate-limited request is retried.
    public var maxRetries: Int
    /// The longest `Retry-After` worth waiting for. A longer one fails the
    /// request at once with ``PriceFetchError/rateLimited(service:retryAfter:)``.
    public var maxRetryWait: Duration
    /// The wait before retrying a 429 that has no `Retry-After`.
    public var retryWaitWithoutHint: Duration

    public init(
        timeout: Duration = .seconds(15), maxRetries: Int = 1, maxRetryWait: Duration = .seconds(5),
        retryWaitWithoutHint: Duration = .seconds(2)
    ) {
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.maxRetryWait = maxRetryWait
        self.retryWaitWithoutHint = retryWaitWithoutHint
    }

    /// 15-second timeout, one retry after at most 5 seconds.
    public static let standard = RequestPolicy()
}
