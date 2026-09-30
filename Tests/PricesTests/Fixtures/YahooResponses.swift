// Recorded responses for Yahoo Finance's chart endpoint (v8/finance/chart).
//
// The build environment's network policy blocks query1.finance.yahoo.com, so
// these follow the endpoint's known format: bar timestamps at the exchange's
// opening time in UTC, closes as float32-precision doubles, and null closes on
// days without trading. Prices are made up, consistent with the example
// library (VWCE.DE closed at 138.42 on 2026-09-30).

enum YahooResponses {
    /// VWCE.DE on XETRA, 14 September to 1 October 2026: bars at 09:00 CEST
    /// (07:00 UTC), no bars at weekends, a null close on 29 September.
    static let vwceSeptember = """
    {"chart":{"result":[{"meta":{"currency":"EUR","symbol":"VWCE.DE","exchangeName":"GER","fullExchangeName":"XETRA",\
    "instrumentType":"ETF","firstTradeDate":1564383600,"regularMarketTime":1790839800,"hasPrePostMarketData":false,\
    "gmtoffset":7200,"timezone":"CEST","exchangeTimezoneName":"Europe/Berlin","regularMarketPrice":139.06,\
    "fiftyTwoWeekHigh":139.4,"fiftyTwoWeekLow":118.62,"longName":"Vanguard FTSE All-World UCITS ETF USD Accumulation",\
    "shortName":"Vanguard FTSE All-World U.ETF R","chartPreviousClose":134.52,"priceHint":2,\
    "currentTradingPeriod":{"pre":{"timezone":"CEST","start":1790838000,"end":1790838000,"gmtoffset":7200},\
    "regular":{"timezone":"CEST","start":1790838000,"end":1790868600,"gmtoffset":7200},\
    "post":{"timezone":"CEST","start":1790868600,"end":1790868600,"gmtoffset":7200}},\
    "dataGranularity":"1d","range":"","validRanges":["1d","5d","1mo","3mo","6mo","1y","2y","5y","ytd","max"]},\
    "timestamp":[1789369200,1789455600,1789542000,1789628400,1789714800,1789974000,1790060400,1790146800,\
    1790233200,1790319600,1790578800,1790665200,1790751600,1790838000],\
    "indicators":{"quote":[{"close":[134.9600067138672,135.39999389648438,135.1199951171875,136.02000427246094,\
    136.3000030517578,135.8800048828125,136.44000244140625,137.10000610351562,136.52000427246094,\
    136.8800048828125,137.63999938964844,null,138.4199981689453,139.05999755859375],\
    "volume":[61234,58210,49876,70311,66120,52019,48833,59120,61477,55890,63021,null,71254,40512],\
    "open":[134.5,135.0,135.44,135.2,136.1,136.2,135.9,136.5,137.0,136.6,136.9,null,137.7,138.5],\
    "high":[135.1,135.52,135.6,136.1,136.4,136.3,136.5,137.2,137.1,137.0,137.7,null,138.5,139.2],\
    "low":[134.3,134.9,135.0,135.1,135.9,135.7,135.8,136.4,136.4,136.4,136.8,null,137.6,138.4]}],\
    "adjclose":[{"adjclose":[134.9600067138672,135.39999389648438,135.1199951171875,136.02000427246094,\
    136.3000030517578,135.8800048828125,136.44000244140625,137.10000610351562,136.52000427246094,\
    136.8800048828125,137.63999938964844,null,138.4199981689453,139.05999755859375]}]}}],"error":null}}
    """

    /// VWCE.DE around Christmas 2026: XETRA closed on 24 and 25 December
    /// (a null bar on the 24th), bars at 09:00 CET (08:00 UTC).
    static let vwceChristmas = """
    {"chart":{"result":[{"meta":{"currency":"EUR","symbol":"VWCE.DE","exchangeName":"GER",\
    "gmtoffset":3600,"timezone":"CET","exchangeTimezoneName":"Europe/Berlin","priceHint":2},\
    "timestamp":[1797235200,1797321600,1797408000,1797494400,1797580800,1797840000,1797926400,1798012800,\
    1798099200,1798444800,1798531200,1798617600],\
    "indicators":{"quote":[{"close":[141.1199951171875,141.5,141.36000061035156,142.02000427246094,\
    141.8800048828125,142.3000030517578,142.66000366210938,142.9199981689453,null,143.10000610351562,\
    143.4199981689453,143.0399932861328]}]}}],"error":null}}
    """

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

    /// A result without `indicators`: the kind of change that should fail clearly.
    static let withoutIndicators = """
    {"chart":{"result":[{"meta":{"currency":"EUR","symbol":"VWCE.DE","priceHint":2},\
    "timestamp":[1790751600]}],"error":null}}
    """

    /// A result without any bars in the range.
    static let noBars = """
    {"chart":{"result":[{"meta":{"currency":"EUR","symbol":"VWCE.DE","priceHint":2},\
    "indicators":{"quote":[{}]}}],"error":null}}
    """

    /// 429 as plain text, as Yahoo sends it.
    static let tooManyRequests = "Too Many Requests\r\n"
}
