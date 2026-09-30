import Foundation
import Model

/// ETF and stock closes from Yahoo Finance's public chart endpoint, e.g.
/// `VWCE.DE` on XETRA or `VWRL.L` in London.
///
///     GET v8/finance/chart/VWCE.DE?period1=…&period2=…&interval=1d&includePrePost=false
///     { "chart": { "result": [{ "meta": { "currency": "EUR", "exchangeTimezoneName": "Europe/Berlin",
///       "priceHint": 2, … }, "timestamp": [1789455600, …],
///       "indicators": { "quote": [{ "close": [137.1199951171875, null, …] }] } }], "error": null } }
///
/// The price is the latest non-null daily close whose trading day, in the
/// exchange's time zone, is on or before the date: Friday's close for a
/// Sunday check-in, and the last trading day before a holiday. On the day
/// itself, while the market is open, it's the latest price.
///
/// The endpoint is unofficial and changes without notice, so the response
/// is read field by field and anything unexpected fails with
/// ``PriceFetchError/malformedResponse(service:detail:)``. Prices in a
/// currency's minor unit (`GBp`, `ZAc`, `ILA`) are converted to the major
/// unit, and closes are rounded to the exchange's `priceHint` decimals.
public struct YahooChartProvider: InstrumentPriceProvider {
    public static let defaultBaseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!

    public var provider: PriceProvider { .yahoo }
    public var source: DataSource { .yahoo }
    public var name: String { "Yahoo Finance" }

    /// How many days before the date to look for a close.
    public var lookbackDays: Int
    /// The `User-Agent` header. Yahoo rejects requests without a browser-like one.
    public var userAgent: String

    private let fetcher: HTTPFetcher
    private let baseURL: URL

    public init(
        client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard,
        baseURL: URL = YahooChartProvider.defaultBaseURL, lookbackDays: Int = 14, userAgent: String = "Mozilla/5.0"
    ) {
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "Yahoo Finance")
        self.baseURL = baseURL
        self.lookbackDays = max(1, lookbackDays)
        self.userAgent = userAgent
    }

    public func quote(for request: QuoteRequest) async throws -> Quote {
        // From the start of the lookback window to two days after the date
        // (UTC), wide enough for exchanges in any time zone; closes after the
        // date in the exchange's time zone are skipped.
        let period1 = Self.epochSeconds(request.date.adding(days: -lookbackDays))
        let period2 = Self.epochSeconds(request.date.adding(days: 2))
        let url = baseURL.appending(segments: [request.symbol], query: [
            ("period1", String(period1)), ("period2", String(period2)),
            ("interval", "1d"), ("includePrePost", "false"),
        ])
        let response = try await fetcher.get(url, headers: ["User-Agent": userAgent])
        try response.requireSuccess(service: name, symbol: request.symbol)
        let envelope = try response.decodeJSON(Envelope.self, service: name)
        return try Self.close(in: envelope, symbol: request.symbol, onOrBefore: request.date, service: name)
    }

    /// The latest close on or before `date` in a chart response.
    static func close(
        in envelope: Envelope, symbol: String, onOrBefore date: CalendarDate, service: String
    ) throws(PriceFetchError) -> Quote {
        guard let chart = envelope.chart else {
            throw .malformedResponse(service: service, detail: "missing chart")
        }
        guard let result = chart.result?.first else {
            if let error = chart.error {
                if error.code == "Not Found" {
                    throw .unknownSymbol(service: service, symbol: symbol, message: error.description)
                }
                throw .noData(service: service, detail: error.description ?? error.code ?? "no chart for \(symbol)")
            }
            throw .malformedResponse(service: service, detail: "missing chart.result")
        }
        guard let currencyCode = result.meta?.currency, !currencyCode.isEmpty else {
            throw .malformedResponse(service: service, detail: "missing chart.result[0].meta.currency")
        }
        guard let timestamps = result.timestamp, !timestamps.isEmpty else {
            throw .noData(service: service, detail: "no trading days for \(symbol) up to \(date)")
        }
        guard let closes = result.indicators?.quote?.first?.close else {
            throw .malformedResponse(service: service, detail: "missing chart.result[0].indicators.quote[0].close")
        }

        let timeZone = result.meta?.exchangeTimezoneName.flatMap(TimeZone.init(identifier:))
            ?? result.meta?.gmtoffset.flatMap(TimeZone.init(secondsFromGMT:))
            ?? TimeZone(identifier: "UTC")!
        var best: (day: CalendarDate, instant: Date, close: Decimal)?
        for (timestamp, close) in zip(timestamps, closes) {
            guard let close, close > 0 else { continue }
            let instant = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let day = CalendarDate(instant, in: timeZone)
            // The latest day wins; on the same day, the later bar (Yahoo
            // sometimes repeats today's bar with the live price).
            if day <= date, best.map({ day >= $0.day }) ?? true { best = (day, instant, close) }
        }
        guard let best else {
            throw .noData(service: service, detail: "no close for \(symbol) on or before \(date)")
        }

        let (currency, divisor) = majorUnit(of: currencyCode)
        var price = best.close / divisor
        if let hint = result.meta?.priceHint, (0...8).contains(hint) {
            price = price.rounded(scale: hint + (divisor == 1 ? 0 : 2))
        } else {
            price = price.rounded(significantDigits: 7)
        }
        return Quote(price: price, currency: currency, observedOn: best.day, observedAt: best.instant)
    }

    /// The major currency and divisor for a minor-unit code: `GBp` is 1/100 GBP.
    static func majorUnit(of code: String) -> (CurrencyCode, Decimal) {
        switch code {
        case "GBp", "GBX": (.gbp, 100)
        case "ZAc", "ZAC": (CurrencyCode("ZAR"), 100)
        case "ILA": (CurrencyCode("ILS"), 100)
        default: (CurrencyCode(code.uppercased()), 1)
        }
    }

    private static func epochSeconds(_ date: CalendarDate) -> Int {
        date.daysSinceEpoch * 86_400
    }

    // MARK: - Response

    struct Envelope: Decodable {
        let chart: Chart?
    }

    struct Chart: Decodable {
        let result: [ChartResult]?
        let error: ChartError?
    }

    struct ChartError: Decodable {
        let code: String?
        let description: String?
    }

    struct ChartResult: Decodable {
        let meta: Meta?
        let timestamp: [Int64]?
        let indicators: Indicators?
    }

    struct Meta: Decodable {
        let currency: String?
        let exchangeTimezoneName: String?
        let gmtoffset: Int?
        let priceHint: Int?
    }

    struct Indicators: Decodable {
        let quote: [QuoteSeries]?
    }

    struct QuoteSeries: Decodable {
        let close: [Decimal?]?
    }
}
