import Model

/// Why a price, FX rate or index value couldn't be fetched. Every case reads
/// as a sentence for the check-in's price list, where the price can then be
/// typed in by hand.
///
/// `service` is the provider's display name, e.g. "Yahoo Finance".
public enum PriceFetchError: Error, Hashable, Sendable, CustomStringConvertible {
    /// No provider is set up for the instrument's price source.
    case unsupportedProvider(PriceProvider)
    /// The request couldn't be sent or no response arrived.
    case network(service: String, message: String)
    /// No response within the per-request timeout.
    case timedOut(service: String, after: Duration)
    /// The service asked to slow down; `retryAfter` is how long it asked to
    /// wait, when it said.
    case rateLimited(service: String, retryAfter: Duration?)
    /// The service refused the request, e.g. an invalid API key or a date
    /// outside what its free tier allows.
    case unauthorized(service: String, message: String?)
    /// The service doesn't know the symbol or currency.
    case unknownSymbol(service: String, symbol: String, message: String?)
    /// Any other unsuccessful HTTP status.
    case httpStatus(service: String, code: Int, message: String?)
    /// The response couldn't be read. Unofficial APIs change without notice.
    case malformedResponse(service: String, detail: String)
    /// The service answered, but has no value for the date.
    case noData(service: String, detail: String)
    /// The service can't provide a value for that date, e.g. it only has
    /// today's spot price.
    case unsupportedDate(service: String, detail: String)
    /// A quote per `from` can't be converted into a price per `to`.
    case unsupportedUnit(from: InstrumentUnit, to: InstrumentUnit)
    /// No FX rate to convert a quote into the instrument's currency.
    case missingFX(from: CurrencyCode, to: CurrencyCode, reason: String?)
    /// A position refers to an instrument that isn't in the library.
    case unknownInstrument(InstrumentID)
    /// The fetch was cancelled.
    case cancelled

    public var description: String {
        switch self {
        case .unsupportedProvider(let provider):
            "There's no \"\(provider)\" price provider yet. Enter the price by hand."
        case .network(let service, let message):
            "Couldn't reach \(service): \(message)"
        case .timedOut(let service, let after):
            "\(service) didn't answer within \(Self.describe(after))."
        case .rateLimited(let service, let retryAfter):
            if let retryAfter {
                "\(service) is limiting requests. Try again in \(Self.describe(retryAfter))."
            } else {
                "\(service) is limiting requests. Try again in a minute."
            }
        case .unauthorized(let service, let message):
            "\(service) refused the request\(Self.suffix(message)). Check the API key in Settings."
        case .unknownSymbol(let service, let symbol, let message):
            "\(service) doesn't know \"\(symbol)\"\(Self.suffix(message))."
        case .httpStatus(let service, let code, let message):
            "\(service) answered with HTTP \(code)\(Self.suffix(message))."
        case .malformedResponse(let service, let detail):
            "\(service)'s response couldn't be read (\(detail)). The service may have changed."
        case .noData(let service, let detail):
            "\(service) has no data: \(detail)."
        case .unsupportedDate(let service, let detail):
            "\(service) \(detail)."
        case .unsupportedUnit(let from, let to):
            "Can't convert a price per \(from) into a price per \(to). Metals can use g, kg or ozt."
        case .missingFX(let from, let to, let reason):
            "No \(from)→\(to) rate to convert the price\(Self.suffix(reason))."
        case .unknownInstrument(let instrument):
            "The instrument \"\(instrument)\" isn't in the library."
        case .cancelled:
            "The fetch was cancelled."
        }
    }

    /// Whether trying again later might succeed.
    public var isTransient: Bool {
        switch self {
        case .network, .timedOut, .rateLimited, .cancelled: true
        case .httpStatus(_, let code, _): code >= 500
        default: false
        }
    }

    private static func suffix(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "" }
        let trimmed = message.hasSuffix(".") ? String(message.dropLast()) : message
        return ": \(trimmed)"
    }

    static func describe(_ duration: Duration) -> String {
        let seconds = duration.timeInterval
        if seconds < 1 { return "\(Int((seconds * 1000).rounded())) ms" }
        let whole = Int(seconds.rounded())
        return whole == 1 ? "1 second" : "\(whole) seconds"
    }
}
