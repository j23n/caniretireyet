import TestSupport

/// Answers from the price APIs' recorded responses, TestSupport's
/// `PriceResponses`, which are shared with the Prices tests and consistent
/// with the example library's September 2026 check-in.
enum Responses {
    /// A client answering every request a check-in around 30 September 2026 makes.
    static func client() -> MockHTTPClient {
        MockHTTPClient([
            "chart/VWCE.DE": PriceResponses.yahooVWCESeptember,
            "symbols=USD": PriceResponses.frankfurterUSDSeptember,
            "simple/price": PriceResponses.coinGeckoBitcoinUSD,
            "price/XAU": PriceResponses.goldAPIGold,
            "prc_hicp_minr": PriceResponses.eurostatHICPItaly,
        ])
    }
}
