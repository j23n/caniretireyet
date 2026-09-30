import Foundation
import Prices

// Recorded responses of the price APIs, copied from the Prices tests
// (Tests/PricesTests/Fixtures). The build environment's network policy blocks
// these hosts, so they follow each API's documented format. The numbers are
// made up, consistent with the example library's September 2026 check-in
// (VWCE.DE 138.42, BTC 111,400 USD, gold 98.4 EUR/g, EUR/USD 1.1398).
enum Responses {
    /// Yahoo Finance, `chart/VWCE.DE`: XETRA bars 14 September to 1 October 2026.
    static let yahooVWCE = """
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

    /// Frankfurter, `2026-09-16..2026-09-30?base=EUR&symbols=USD`.
    static let frankfurterUSD = """
    {"amount":1.0,"base":"EUR","start_date":"2026-09-16","end_date":"2026-09-30","rates":{\
    "2026-09-16":{"USD":1.1352},"2026-09-17":{"USD":1.1361},"2026-09-18":{"USD":1.1349},\
    "2026-09-21":{"USD":1.1366},"2026-09-22":{"USD":1.1374},"2026-09-23":{"USD":1.138},\
    "2026-09-24":{"USD":1.1369},"2026-09-25":{"USD":1.1371},"2026-09-28":{"USD":1.1385},\
    "2026-09-29":{"USD":1.139},"2026-09-30":{"USD":1.1398}}}
    """

    /// CoinGecko, `simple/price?ids=bitcoin&vs_currencies=usd…`.
    static let coinGeckoBitcoinUSD = #"{"bitcoin":{"usd":111400,"last_updated_at":1790758680}}"#

    /// gold-api.com, `price/XAU`: USD per troy ounce.
    static let goldAPIGold = """
    {"currency":"USD","currencySymbol":"$","exchangeRate":1,"name":"Gold","price":3488.449951,"symbol":"XAU",\
    "updatedAt":"2026-09-30T08:59:47Z","updatedAtReadable":"a few seconds ago"}
    """

    /// Eurostat, `prc_hicp_minr` for Italy: July and August 2026 (September isn't published yet).
    static let eurostatHICP = """
    {"version":"2.0","class":"dataset",\
    "label":"Harmonised index of consumer prices (HICP) - monthly data (index)","source":"ESTAT",\
    "updated":"2026-09-17T11:00:00+0200","value":{"0":128.1,"1":128.41},"status":{"1":"p"},\
    "id":["freq","unit","coicop18","geo","time"],"size":[1,1,1,1,2],\
    "dimension":{"freq":{"label":"Time frequency","category":{"index":{"M":0},"label":{"M":"Monthly"}}},\
    "unit":{"label":"Unit of measure","category":{"index":{"I15":0},"label":{"I15":"Index, 2015=100"}}},\
    "coicop18":{"label":"Classification of individual consumption by purpose (COICOP 2018)",\
    "category":{"index":{"TOTAL":0},"label":{"TOTAL":"All-items HICP"}}},\
    "geo":{"label":"Geopolitical entity (reporting)","category":{"index":{"IT":0},"label":{"IT":"Italy"}}},\
    "time":{"label":"Time","category":{"index":{"2026-07":0,"2026-08":1},\
    "label":{"2026-07":"2026-07","2026-08":"2026-08"}}}},\
    "extension":{"lang":"EN","agencyId":"ESTAT","id":"PRC_HICP_MINR","version":"1.0",\
    "datastructure":{"agencyId":"ESTAT","id":"PRC_HICP_MINR","version":"1.0"},\
    "annotation":[{"type":"OBS_COUNT","title":"2"},{"type":"OBS_PERIOD_OVERALL_OLDEST","title":"1996-01"},\
    {"type":"OBS_PERIOD_OVERALL_LATEST","title":"2026-08"}],\
    "positions-with-no-data":{"freq":[],"unit":[],"coicop18":[],"geo":[],"time":[]}}}
    """

    /// A client answering every request a check-in around 30 September 2026 makes.
    static func client() -> MockHTTPClient {
        MockHTTPClient([
            "chart/VWCE.DE": yahooVWCE,
            "symbols=USD": frankfurterUSD,
            "simple/price": coinGeckoBitcoinUSD,
            "price/XAU": goldAPIGold,
            "prc_hicp_minr": eurostatHICP,
        ])
    }
}
