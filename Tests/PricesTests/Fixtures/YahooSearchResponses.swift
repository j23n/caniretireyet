// Responses of Yahoo Finance's search endpoint (v1/finance/search), in its
// known format. The build environment's network policy blocks Yahoo
// Finance, so these are written by hand: real symbols, trimmed to the
// fields the search reads and a few it ignores. The search for VWCE's
// ISIN, which the CLI's tests use too, is TestSupport's `PriceResponses`.

enum YahooSearchResponses {
    /// A London listing quoted in pence, a US stock, and entries to leave
    /// out or read leniently: one without a symbol, a duplicate, a null, and
    /// a field of the wrong type.
    static let mixed = """
    {"count":6,"quotes":[\
    {"exchange":"LSE","shortname":"VANGUARD FTSE ALL-WORLD","quoteType":"ETF","symbol":"VWRL.L",\
    "exchDisp":"London","currency":"GBp","isYahooFinance":true},\
    {"exchange":"NMS","shortname":"Apple Inc.","quoteType":"EQUITY","symbol":"AAPL","exchDisp":"NASDAQ",\
    "typeDisp":"Equity","isYahooFinance":true},\
    {"exchange":"NMS","shortname":"no symbol","quoteType":"EQUITY","isYahooFinance":true},\
    {"exchange":"NMS","shortname":"Apple again","quoteType":"EQUITY","symbol":"AAPL","isYahooFinance":true},\
    null,\
    {"symbol":"BTC-EUR","shortname":"Bitcoin EUR","quoteType":"CRYPTOCURRENCY","exchange":"CCC",\
    "exchDisp":"CCC","score":12,"isYahooFinance":"yes"}\
    ],"news":[]}
    """

    /// Nothing found.
    static let nothing = """
    {"explains":[],"count":0,"quotes":[],"news":[],"nav":[],"lists":[],"researchReports":[],"totalTime":12}
    """

    /// A query Yahoo Finance rejects, with HTTP 400.
    static let badRequest = """
    {"finance":{"result":null,"error":{"code":"Bad Request","description":"Invalid Search Query"}}}
    """
}
