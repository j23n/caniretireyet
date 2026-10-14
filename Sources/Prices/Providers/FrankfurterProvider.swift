import Foundation
import Model

/// ECB reference rates through Frankfurter (`frankfurter.dev`): free, no key.
///
/// The ECB publishes one rate per working day around 16:00 CET, none on
/// weekends and TARGET holidays. The service asks for the days leading up
/// to the dates it needs and takes the latest rate on or before each
/// (``FXHistory/rate(onOrBefore:)``), so a Sunday gets Friday's rate and
/// Easter Monday gets Thursday's.
///
///     GET /v1/2026-09-16..2026-09-30?base=EUR&symbols=USD
///     { "amount": 1.0, "base": "EUR", "start_date": "2026-09-16", "end_date": "2026-09-30",
///       "rates": { "2026-09-16": { "USD": 1.1352 }, …, "2026-09-30": { "USD": 1.1398 } } }
public struct FrankfurterProvider: Sendable {
    static let baseURL = URL(string: "https://api.frankfurter.dev/v1/")!
    /// The source written on fetched FX records.
    public var source: DataSource { .ecb }
    public var name: String { "Frankfurter (ECB)" }

    private let fetcher: HTTPFetcher

    public init(client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "Frankfurter (ECB)")
    }

    /// Every rate published from `start` through `end` (1 `base` = rate ×
    /// `quote`), in one request of Frankfurter's time series
    /// (`/v1/<start>..<end>`). Frankfurter may thin a range longer than a
    /// year out to about one rate a week; the history says so
    /// (``FXHistory/isWeekly``) and allows for it.
    public func rates(base: CurrencyCode, quote: CurrencyCode, from start: CalendarDate,
                      through end: CalendarDate) async throws -> FXHistory {
        if base == quote {
            return FXHistory(rates: [FXObservation(rate: 1, observedOn: start), FXObservation(rate: 1, observedOn: end)])
        }
        let pair = "\(base)/\(quote)"
        let url = Self.baseURL.appending(segments: ["\(start)..\(end)"],
                                         query: [("base", base.rawValue), ("symbols", quote.rawValue)])
        let response = try await fetcher.get(url)
        try response.requireSuccess(service: name, symbol: pair)
        let body = try response.decodeJSON(TimeSeries.self, service: name)
        if let answeredBase = body.base, answeredBase != base.rawValue {
            throw PriceFetchError.malformedResponse(service: name, detail: "rates are for \(answeredBase), not \(base)")
        }
        return FXHistory(rates: body.rates.compactMap { key, values in
            guard let day = CalendarDate(key), let rate = values[quote.rawValue], rate > 0 else { return nil }
            return FXObservation(rate: rate, observedOn: day)
        })
    }

    private struct TimeSeries: Decodable {
        let base: String?
        let rates: [String: [String: Decimal]]
    }
}
