import Foundation
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
            "chart/BTC-USD": PriceResponses.yahooBitcoinSeptember,
            "price/XAU": PriceResponses.goldAPIGold,
            "prc_hicp_minr": PriceResponses.eurostatHICPItaly,
        ])
    }
}

extension TemporaryFolder {
    /// A copy of the example library with bitcoin priced from Yahoo Finance's
    /// `BTC-USD` pair, and its recorded prices from there too.
    static func exampleLibraryOnYahoo() throws -> TemporaryFolder {
        let folder = try exampleLibrary()
        try folder.write("instruments/btc.json", try folder.text("instruments/btc.json").replacingOccurrences(
            of: #""provider": "coingecko", "symbol": "bitcoin""#, with: #""provider": "yahoo", "symbol": "BTC-USD""#))
        for path in Fixtures.allJSONFiles where path.hasPrefix("history/") {
            try folder.write(path, try folder.text(path).replacingOccurrences(
                of: #""source": "coingecko""#, with: #""source": "yahoo""#))
        }
        return folder
    }
}
