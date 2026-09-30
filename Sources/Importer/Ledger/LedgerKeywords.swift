import Model

/// Words the journal import uses to classify ledger accounts and
/// commodities, in English and a few other languages. All folded
/// (lowercase, no accents).
enum LedgerKeywords {
    // MARK: Account roots

    /// Top-level accounts of debts.
    static let liabilityRoots: Set<String> = [
        "liabilities", "liability", "passivita", "passivo", "passiva", "passifs", "pasivos", "verbindlichkeiten",
        "debts", "debiti",
    ]
    static let incomeRoots: Set<String> = [
        "income", "incomes", "revenue", "revenues", "entrate", "ricavi", "proventi", "redditi", "einnahmen", "ertrage",
        "revenus", "produits", "ingresos",
    ]
    static let expenseRoots: Set<String> = [
        "expenses", "expense", "spese", "uscite", "costi", "ausgaben", "aufwendungen", "depenses", "charges", "gastos",
    ]
    static let equityRoots: Set<String> = ["equity", "patrimonio", "capitale", "eigenkapital", "capitaux", "capital"]

    // MARK: Returns

    /// Income accounts whose postings are returns: dividends, interest, gains, staking.
    static let incomeReturns = [
        "dividend", "dividends", "dividendi", "dividendo", "divs", "interest", "interests", "interessi", "interesse",
        "zinsen", "interets", "intereses", "gain", "gains", "capitalgains", "capgains", "plusvalenza", "plusvalenze",
        "minusvalenza", "minusvalenze", "realized", "unrealized", "staking", "reward", "rewards", "yield", "coupon",
        "coupons", "cedola", "cedole", "distribution", "distributions", "airdrop", "airdrops",
    ]
    /// Expense accounts whose postings are part of the return: fees and commissions.
    static let expenseReturns = [
        "fee", "fees", "commission", "commissions", "commissione", "commissioni", "gebuhren", "frais", "comisiones",
        "bank charges", "broker", "brokerage", "trading",
    ]

    // MARK: Grouping accounts

    /// Subaccounts that are parts of one account, e.g. `Directa:Cash`.
    static let buckets: Set<String> = [
        "cash", "liquidita", "liquidity", "contanti", "uninvested", "settled", "unsettled", "pending", "margin",
        "available", "positions", "holdings", "securities", "titoli", "stocks", "shares", "etf", "etfs", "funds",
        "fondi", "bonds", "obbligazioni", "coins", "portfolio", "portafoglio",
    ]
    /// Names too generic to stand for an account on their own, e.g. `Wallet`.
    static let generic: Set<String> = [
        "cash", "bank", "banks", "banca", "banche", "checking", "current", "savings", "card", "cards", "creditcard",
        "wallet", "wallets", "broker", "brokers", "brokerage", "conto", "conti", "carta", "carte", "account",
        "accounts", "investments", "investimenti", "crypto", "deposit", "deposito", "loan", "loans", "mortgage",
    ]

    // MARK: Commodities

    /// Currency symbols.
    static let currencySymbols: [String: CurrencyCode] = [
        "€": "EUR", "$": "USD", "US$": "USD", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW", "₺": "TRY",
        "R$": "BRL", "C$": "CAD", "A$": "AUD", "Fr.": "CHF", "zł": "PLN", "₪": "ILS", "฿": "THB",
    ]

    /// ISO 4217 codes of currencies (not precious metals, which are instruments).
    static let currencyCodes: Set<String> = [
        "AED", "ARS", "AUD", "BGN", "BRL", "CAD", "CHF", "CLP", "CNY", "COP", "CZK", "DKK", "EGP", "EUR", "GBP",
        "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KES", "KRW", "MAD", "MXN", "MYR", "NGN", "NOK", "NZD",
        "PEN", "PHP", "PKR", "PLN", "QAR", "RON", "RSD", "RUB", "SAR", "SEK", "SGD", "THB", "TRY", "TWD", "UAH",
        "USD", "VND", "ZAR",
    ]

    /// Tickers of well-known cryptocurrencies.
    static let cryptoTickers: Set<String> = [
        "BTC", "XBT", "ETH", "SOL", "ADA", "DOT", "XRP", "LTC", "DOGE", "BNB", "AVAX", "MATIC", "POL", "LINK", "ATOM",
        "XMR", "XLM", "TRX", "USDT", "USDC", "DAI", "EURC", "SHIB", "UNI", "ALGO", "NEAR", "ARB", "OP", "TON", "BCH",
        "FIL", "APT", "SUI", "HBAR", "ICP", "VET", "EOS", "XTZ", "AAVE", "MKR", "SAND", "MANA", "CRO", "KAS", "PEPE",
        "SATS",
    ]

    /// Metals: the gold-api symbol and whether it's gold.
    static let metals: [String: (symbol: String, isGold: Bool)] = [
        "XAU": ("XAU", true), "GOLD": ("XAU", true), "ORO": ("XAU", true), "AU": ("XAU", true),
        "XAG": ("XAG", false), "SILVER": ("XAG", false), "ARGENTO": ("XAG", false), "AG": ("XAG", false),
        "XPT": ("XPT", false), "PLATINUM": ("XPT", false), "XPD": ("XPD", false),
    ]

    /// Tickers of common ETFs, so a ticker is proposed as an ETF rather than a stock.
    static let etfTickers: Set<String> = [
        "VWCE", "VWRL", "VWRA", "VWRP", "SWDA", "IWDA", "EUNL", "CSPX", "CSSPX", "SXR8", "VUSA", "VUAA", "EIMI",
        "IEMA", "AGGH", "XDWD", "SPPW", "VHYL", "XDEM", "ZPRV", "ZPRX", "IUSN", "WSML", "EXSA", "MEUD", "VEUR",
        "VFEM", "EMIM", "IS3N", "SGLD", "PHAU", "VGWL", "VT", "VTI", "VOO", "VXUS", "SPY", "IVV", "QQQ", "BND",
        "SCHD", "VEA", "VWO", "AGG", "IWM", "GLD", "IAU",
    ]
}
