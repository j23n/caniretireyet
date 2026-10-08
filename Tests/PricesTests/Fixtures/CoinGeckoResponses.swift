// Recorded responses for CoinGecko.
//
// The build environment's network policy blocks api.coingecko.com, so these
// follow CoinGecko's documented formats for `simple/price`,
// `coins/{id}/history` and `search`, and its documented error bodies. Prices
// are made up, consistent with the example library. The coins in the search
// results (Moonstone and friends) are made up too. Bitcoin's price in dollars,
// which the CLI's tests use too, is TestSupport's `PriceResponses`.

enum CoinGeckoResponses {
    /// `GET simple/price?ids=ethereum&vs_currencies=eur&…`, for the ticker `ETH`.
    static let spotEthereumEUR = #"{"ethereum":{"eur":3812.0625,"last_updated_at":1790758680}}"#

    /// `GET coins/ethereum/history?date=01-04-2026&localization=false`.
    static let historyEthereumEndOfMarch = """
    {"id":"ethereum","symbol":"eth","name":"Ethereum",\
    "image":{"thumb":"https://coin-images.coingecko.com/coins/images/279/thumb/ethereum.png?1696501628"},\
    "market_data":{"current_price":{"btc":0.0201,"eur":1612.34,"usd":1790.05},\
    "market_cap":{"eur":194612345678.9,"usd":216012345678.9}}}
    """

    /// `GET search?query=MOON`: several coins with the ticker MOON. The
    /// best-ranked is Moonstone (287), tied with Moon DAO, which comes later;
    /// Moonpaw ranks better but its ticker only starts with MOON.
    static let searchMoon = """
    {"coins":[\
    {"id":"moonshot-cat","name":"Moonshot Cat","api_symbol":"moonshot-cat","symbol":"MOON","market_cap_rank":null,\
    "thumb":"https://coin-images.coingecko.com/coins/images/90001/thumb/moonshot-cat.png",\
    "large":"https://coin-images.coingecko.com/coins/images/90001/large/moonshot-cat.png"},\
    {"id":"moon-token","name":"Moon Token","api_symbol":"moon-token","symbol":"MOON","market_cap_rank":1432,\
    "thumb":"https://coin-images.coingecko.com/coins/images/90002/thumb/moon-token.png",\
    "large":"https://coin-images.coingecko.com/coins/images/90002/large/moon-token.png"},\
    {"id":"moonpaw","name":"Moonpaw","api_symbol":"moonpaw","symbol":"MOONPAW","market_cap_rank":95,\
    "thumb":"https://coin-images.coingecko.com/coins/images/90003/thumb/moonpaw.png",\
    "large":"https://coin-images.coingecko.com/coins/images/90003/large/moonpaw.png"},\
    {"id":"moonstone","name":"Moonstone","api_symbol":"moonstone","symbol":"MOON","market_cap_rank":287,\
    "thumb":"https://coin-images.coingecko.com/coins/images/90004/thumb/moonstone.png",\
    "large":"https://coin-images.coingecko.com/coins/images/90004/large/moonstone.png"},\
    {"id":"moon-dao","name":"Moon DAO","api_symbol":"moon-dao","symbol":"MOON","market_cap_rank":287,\
    "thumb":"https://coin-images.coingecko.com/coins/images/90005/thumb/moon-dao.png",\
    "large":"https://coin-images.coingecko.com/coins/images/90005/large/moon-dao.png"}],\
    "exchanges":[{"id":"moonex","name":"MoonEx","market_type":"spot",\
    "thumb":"https://coin-images.coingecko.com/markets/images/901/thumb/moonex.png",\
    "large":"https://coin-images.coingecko.com/markets/images/901/large/moonex.png"}],\
    "icos":[],"categories":[{"id":"moon-ecosystem","name":"Moon Ecosystem"}],"nfts":[]}
    """

    /// `GET search?query=XYZ`: coins that only resemble the query.
    static let searchNoMatch = """
    {"coins":[\
    {"id":"xyzzy","name":"Xyzzy","api_symbol":"xyzzy","symbol":"XYZZY","market_cap_rank":null,\
    "thumb":"https://coin-images.coingecko.com/coins/images/90006/thumb/xyzzy.png",\
    "large":"https://coin-images.coingecko.com/coins/images/90006/large/xyzzy.png"}],\
    "exchanges":[],"icos":[],"categories":[],"nfts":[]}
    """

    /// `GET simple/price?ids=moonstone&vs_currencies=usd&…`.
    static let spotMoonstoneUSD = #"{"moonstone":{"usd":0.4187,"last_updated_at":1790758680}}"#

    /// `GET coins/moonstone/history?date=…`: the same snapshot for any date.
    static let historyMoonstone = """
    {"id":"moonstone","symbol":"moon","name":"Moonstone",\
    "market_data":{"current_price":{"eur":0.3561,"usd":0.3952},"market_cap":{"eur":35610000.0,"usd":39520000.0}}}
    """

    /// `GET simple/price?ids=bitcoin&vs_currencies=eur&…`.
    static let spotEUR = #"{"bitcoin":{"eur":97736.4568,"last_updated_at":1790758680}}"#

    /// `GET simple/price?ids=not-a-coin&…`: an unknown ID gives an empty object.
    static let spotUnknown = "{}"

    /// `GET coins/bitcoin/history?date=01-04-2026&localization=false`: the
    /// snapshot at 00:00 UTC on 1 April, i.e. the end of 31 March.
    static let historyEndOfMarch = """
    {"id":"bitcoin","symbol":"btc","name":"Bitcoin",\
    "image":{"thumb":"https://coin-images.coingecko.com/coins/images/1/thumb/bitcoin.png?1696501400",\
    "small":"https://coin-images.coingecko.com/coins/images/1/small/bitcoin.png?1696501400"},\
    "market_data":{"current_price":{"btc":1.0,"chf":71019.24,"eur":80076.47,"gbp":68521.9,"usd":88900.12},\
    "market_cap":{"eur":1589461234567.1,"usd":1764612345678.9},\
    "total_volume":{"eur":28912345678.4,"usd":32098765432.1}},\
    "community_data":{"facebook_likes":null,"reddit_average_posts_48h":0.0,"reddit_average_comments_48h":0.0,\
    "reddit_subscribers":null,"reddit_accounts_active_48h":null},\
    "developer_data":{"forks":36426,"stars":73168,"subscribers":3967,"total_issues":7743,"closed_issues":7380,\
    "pull_requests_merged":11215,"pull_request_contributors":846,\
    "code_additions_deletions_4_weeks":{"additions":1570,"deletions":-1948},"commit_count_4_weeks":108},\
    "public_interest_stats":{"alexa_rank":null,"bing_matches":null}}
    """

    /// A history snapshot from before the coin had market data.
    static let historyWithoutMarketData = """
    {"id":"bitcoin","symbol":"btc","name":"Bitcoin",\
    "image":{"thumb":"https://coin-images.coingecko.com/coins/images/1/thumb/bitcoin.png?1696501400"}}
    """

    /// 429 on the public API.
    static let rateLimited = """
    {"status":{"error_code":429,"error_message":"You've exceeded the Rate Limit. Please visit \
    https://www.coingecko.com/en/api/pricing to subscribe to our API plans for higher rate limits."}}
    """

    /// 404 for an unknown coin ID on `coins/{id}/history`.
    static let coinNotFound = #"{"error":"coin not found"}"#

    /// 401 for a history date beyond the public API's 365 days.
    static let beyondTimeRange = """
    {"error":{"status":{"timestamp":"2026-09-30T09:00:00.000+00:00","error_code":10012,\
    "error_message":"Your request exceeds the allowed time range. Public API users are limited to querying \
    historical data within the past 365 days."}}}
    """

    /// 400 when a Pro key is sent to the public host.
    static let wrongKey = """
    {"status":{"error_code":10010,"error_message":"If you are using Pro API key, please change your root URL \
    from api.coingecko.com to pro-api.coingecko.com"}}
    """
}

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
