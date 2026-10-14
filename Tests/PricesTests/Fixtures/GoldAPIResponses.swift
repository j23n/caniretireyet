// Recorded responses for gold-api.com, from its documented `price/{symbol}`
// format (the host is blocked here too). Spot prices are made up. Gold's,
// which the CLI's tests use too, is TestSupport's `PriceResponses`.
enum GoldAPIResponses {
    /// `GET price/XAG`, without the optional currency fields.
    static let silver = """
    {"name":"Silver","price":41.279999,"symbol":"XAG","updatedAt":"2026-09-30T08:59:47Z",\
    "updatedAtReadable":"a few seconds ago"}
    """

    /// 404 for an unknown symbol.
    static let unknownSymbol = #"{"error":"Symbol not found"}"#
}
