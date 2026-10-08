// Recorded responses for Frankfurter (ECB reference rates).
//
// The build environment's network policy blocks api.frankfurter.dev, so these
// follow Frankfurter's documented time-series format. The rates are made up,
// consistent with the example library (EUR/USD 1.1398 on 2026-09-30). The
// September dollar rates, which the CLI's tests use too, are TestSupport's
// `PriceResponses`.

enum FrankfurterResponses {
    /// `GET /v1/2026-03-23..2026-04-06?base=EUR&symbols=USD`: no rates on the
    /// TARGET holidays Good Friday (3 April) and Easter Monday (6 April 2026).
    static let easter2026 = """
    {"amount":1.0,"base":"EUR","start_date":"2026-03-23","end_date":"2026-04-02","rates":{\
    "2026-03-23":{"USD":1.1041},"2026-03-24":{"USD":1.1058},"2026-03-25":{"USD":1.1063},\
    "2026-03-26":{"USD":1.1079},"2026-03-27":{"USD":1.1091},"2026-03-30":{"USD":1.1096},\
    "2026-03-31":{"USD":1.1102},"2026-04-01":{"USD":1.1094},"2026-04-02":{"USD":1.1087}}}
    """

    /// `GET /v1/2026-09-16..2026-09-30?base=EUR&symbols=CHF`.
    static let septemberCHF = """
    {"amount":1.0,"base":"EUR","start_date":"2026-09-16","end_date":"2026-09-30","rates":{\
    "2026-09-28":{"CHF":0.9318},"2026-09-29":{"CHF":0.9309},"2026-09-30":{"CHF":0.9312}}}
    """

    /// No rates in the range (e.g. a range before the currency was published).
    static let empty = """
    {"amount":1.0,"base":"EUR","start_date":"2026-09-16","end_date":"2026-09-30","rates":{}}
    """

    /// 404 for a currency the ECB doesn't publish.
    static let notFound = #"{"message":"not found"}"#
}
