import Foundation
import Model

/// ECB reference rates through Frankfurter (`frankfurter.dev`): free, no key.
///
/// The ECB publishes one rate per working day around 16:00 CET, none on
/// weekends and TARGET holidays. The provider asks for the days leading up
/// to the date and takes the latest one on or before it, so a Sunday gets
/// Friday's rate and Easter Monday gets Thursday's.
///
///     GET /v1/2026-09-16..2026-09-30?base=EUR&symbols=USD
///     { "amount": 1.0, "base": "EUR", "start_date": "2026-09-16", "end_date": "2026-09-30",
///       "rates": { "2026-09-16": { "USD": 1.1352 }, …, "2026-09-30": { "USD": 1.1398 } } }
public struct FrankfurterProvider: FXRateProvider {
    public static let defaultBaseURL = URL(string: "https://api.frankfurter.dev/v1/")!

    public var source: DataSource { .ecb }
    public var name: String { "Frankfurter (ECB)" }

    /// How many days before the date to look for a rate. Covers weekends
    /// and the longest run of holidays.
    public var lookbackDays: Int

    private let fetcher: HTTPFetcher
    private let baseURL: URL

    public init(
        client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard,
        baseURL: URL = FrankfurterProvider.defaultBaseURL, lookbackDays: Int = 14
    ) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "Frankfurter (ECB)")
        self.baseURL = baseURL
        self.lookbackDays = max(1, lookbackDays)
    }

    public func rate(base: CurrencyCode, quote: CurrencyCode, onOrBefore date: CalendarDate) async throws -> FXObservation {
        if base == quote { return FXObservation(rate: 1, observedOn: date) }
        let pair = "\(base)/\(quote)"
        let range = "\(date.adding(days: -lookbackDays))..\(date)"
        let url = baseURL.appending(segments: [range], query: [("base", base.rawValue), ("symbols", quote.rawValue)])
        let response = try await fetcher.get(url)
        try response.requireSuccess(service: name, symbol: pair)
        let body = try response.decodeJSON(TimeSeries.self, service: name)
        if let answeredBase = body.base, answeredBase != base.rawValue {
            throw PriceFetchError.malformedResponse(service: name, detail: "rates are for \(answeredBase), not \(base)")
        }
        return try Self.latest(in: body.rates, quote: quote, onOrBefore: date, pair: pair, service: name)
    }

    /// The latest rate for `quote` dated on or before `date`.
    static func latest(
        in rates: [String: [String: Decimal]], quote: CurrencyCode, onOrBefore date: CalendarDate, pair: String,
        service: String
    ) throws(PriceFetchError) -> FXObservation {
        let candidates = rates.compactMap { key, values -> FXObservation? in
            guard let day = CalendarDate(key), day <= date, let rate = values[quote.rawValue], rate > 0 else {
                return nil
            }
            return FXObservation(rate: rate, observedOn: day)
        }
        guard let latest = candidates.max(by: { $0.observedOn < $1.observedOn }) else {
            throw .noData(service: service, detail: "no \(pair) rate on or before \(date)")
        }
        return latest
    }

    private struct TimeSeries: Decodable {
        let base: String?
        let rates: [String: [String: Decimal]]
    }
}
