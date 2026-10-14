// Recorded responses for Yahoo Finance's chart endpoint (v8/finance/chart).
//
// The build environment's network policy blocks query1.finance.yahoo.com, so
// these follow the endpoint's known format: bar timestamps at the exchange's
// opening time in UTC, closes as float32-precision doubles, and null closes on
// days without trading. Prices are made up, consistent with the example
// library (VWCE.DE closed at 138.42 on 2026-09-30). VWCE.DE's September bars,
// which the CLI's tests use too, are TestSupport's `PriceResponses`.

enum YahooResponses {
    /// VWRL.L on the London Stock Exchange, quoted in pence (`GBp`).
    static let vwrlPence = """
    {"chart":{"result":[{"meta":{"currency":"GBp","symbol":"VWRL.L","exchangeName":"LSE","gmtoffset":3600,\
    "timezone":"BST","exchangeTimezoneName":"Europe/London","priceHint":2},\
    "timestamp":[1790233200,1790319600,1790578800,1790665200,1790751600],\
    "indicators":{"quote":[{"close":[10466.0,10490.5,10512.0,10501.0,10523.5]}]}}],"error":null}}
    """

    /// FPH.NZ in Auckland (NZDT from 27 September 2026): bars at 10:00 local,
    /// i.e. 21:00 or 22:00 UTC on the previous calendar day.
    static let fphAuckland = """
    {"chart":{"result":[{"meta":{"currency":"NZD","symbol":"FPH.NZ","exchangeName":"NZE","gmtoffset":46800,\
    "timezone":"NZDT","exchangeTimezoneName":"Pacific/Auckland","priceHint":2},\
    "timestamp":[1790200800,1790287200,1790542800,1790629200,1790715600],\
    "indicators":{"quote":[{"close":[38.11000061035156,38.2400016784668,38.5,38.70000076293945,39.0]}]}}],\
    "error":null}}
    """

    /// 404 for an unknown symbol.
    static let notFound = """
    {"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}
    """

    /// A result without any bars in the range.
    static let noBars = """
    {"chart":{"result":[{"meta":{"currency":"EUR","symbol":"VWCE.DE","priceHint":2},\
    "indicators":{"quote":[{}]}}],"error":null}}
    """
}
