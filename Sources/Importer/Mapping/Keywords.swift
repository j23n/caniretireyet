import Foundation
import Model

/// Header and name words, in English and Italian, that the importer uses to
/// propose a mapping and to suggest kinds. All folded (lowercase, no accents).
enum Keywords {
    // MARK: Long-layout fields

    static let account = ["account", "conto", "rapporto", "portafoglio", "portfolio", "broker", "banca", "bank",
                          "istituto", "nome", "name"]
    static let instrument = ["instrument", "strumento", "titolo", "ticker", "symbol", "simbolo", "isin",
                             "security", "asset", "prodotto"]
    static let currency = ["currency", "valuta", "divisa", "ccy", "moneta"]
    static let base = ["base", "base currency", "from"]
    static let quote = ["quote", "quote currency", "to"]

    // MARK: Value targets

    static let quantity = ["quantita", "quantity", "qty", "qta", "units", "unita", "shares", "quote", "pezzi",
                           "nominale", "holding"]
    static let price = ["prezzo", "price", "quotazione", "close", "chiusura", "nav", "last"]
    static let costBasis = ["valore di carico", "cost basis", "costo", "cost", "carico", "book value"]
    /// Averages per unit, which aren't a purchase cost.
    static let average = ["medio", "media", "average", "avg", "pmc"]
    static let cash = ["cash", "liquidita", "contanti"]
    static let fx = ["cambio", "fx", "exchange rate", "tasso di cambio", "rate"]
    static let balance = ["saldo", "balance", "valore", "value", "controvalore", "market value", "importo", "amount"]
    /// Wide-layout columns that are computed or commentary, not account values.
    static let computed = ["totale", "total", "totali", "somma", "sum", "patrimonio", "net worth", "networth",
                           "variazione", "delta", "change", "differenza", "diff", "rendimento", "return",
                           "performance", "note", "notes", "nota", "commento", "comment", "commenti",
                           "descrizione", "description"]

    // MARK: Trades layout (headers with camel case split: `NetCash` → `net cash`)

    /// A column of trade types.
    static let tradeType = ["tipo", "tipo operazione", "operazione", "causale", "type", "transaction type", "action",
                            "buy sell", "segno", "tipologia", "movimento"]
    /// A column of instrument names, tickers or ISINs.
    static let tradeInstrument = instrument + ["product", "nome titolo", "descrizione titolo", "securities"]
    /// A column naming the account.
    static let tradeAccount = ["account", "conto", "rapporto", "portafoglio", "portfolio", "dossier", "account id"]
    /// A column of free text for the note.
    static let tradeNote = ["descrizione", "description", "note", "notes", "nota", "commento", "comment", "dettagli",
                            "details"]
    /// Number columns in another currency than the account's, and rates: not imported.
    static let tradeSkip = ["local", "locale", "cambio", "exchange rate", "fx", "rate", "tasso"]
    /// The cash a trade moved, net of fees and tax.
    static let tradeNet = ["netto", "net", "net cash", "netcash", "total", "totale", "net amount"]
    /// The value before fees and tax, said outright.
    static let tradeGrossMarkers = ["lordo", "gross"]
    static let tradeGross = ["controvalore", "value", "valore", "proceeds"]
    static let tradeAmount = ["importo", "amount", "cash", "somma"]
    static let tradeFees = ["commissioni", "commissione", "commission", "commissions", "fee", "fees", "spese", "costi",
                            "costs", "transaction costs", "ibcommission", "comm"]
    static let tradeTax = ["tasse", "tassa", "tax", "taxes", "imposte", "imposta", "ritenuta", "ritenute", "bollo",
                           "withholding"]
    static let tradeRatio = ["ratio", "split ratio", "rapporto"]

    /// Words removed from a header to get the name it stands for:
    /// `BTC (qtà)` → `BTC`, `Prezzo VWCE` → `VWCE`.
    static let headerNoise = quantity + price + costBasis + cash + balance

    // MARK: Kinds

    /// Account kinds by name, in the order they're tested.
    static let accountKinds: [(AccountKind, [String])] = [
        (.mortgage, ["mutuo", "mortgage"]),
        (.loan, ["prestito", "finanziamento", "loan", "debito", "debt"]),
        (.creditCard, ["carta di credito", "credit card", "carta", "card", "amex", "visa", "mastercard"]),
        (.pensionFund, ["fondo pensione", "pension", "pensione", "previdenza", "401k", "ira", "pip"]),
        (.tfr, ["tfr", "liquidazione"]),
        (.property, ["casa", "house", "home", "immobile", "appartamento", "apartment", "flat", "property",
                     "real estate"]),
        (.vehicle, ["auto", "car", "macchina", "moto", "vehicle"]),
        (.crypto, ["crypto", "cripto", "bitcoin", "btc", "eth", "ethereum", "wallet", "ledger", "coinbase",
                   "binance", "kraken"]),
        (.metals, ["oro", "gold", "argento", "silver", "metal", "metalli", "metals"]),
        (.savings, ["deposito", "risparmio", "savings", "libretto", "vincolato", "time deposit"]),
        (.brokerage, ["broker", "brokerage", "directa", "degiro", "ibkr", "interactive brokers", "etf", "azioni",
                      "stocks", "dossier", "trading", "invest", "investment", "investments", "titoli", "sim"]),
        (.cash, ["conto", "conto corrente", "bank", "banca", "checking", "current", "cash", "contanti", "paypal",
                 "revolut", "n26", "bancoposta"]),
    ]

    /// Instrument kinds by name, in the order they're tested.
    static let instrumentKinds: [(InstrumentKind, [String])] = [
        (.crypto, ["btc", "bitcoin", "eth", "ethereum", "sol", "solana", "ada", "cardano", "crypto"]),
        (.metal, ["oro", "gold", "xau", "argento", "silver", "xag", "platino", "platinum"]),
        (.etc, ["etc"]),
        (.bond, ["btp", "bot", "bond", "bonds", "obbligazione", "obbligazioni", "treasury", "bund"]),
        (.etf, ["etf", "ucits", "ishares", "vanguard", "xtrackers", "amundi", "spdr", "lyxor", "invesco"]),
        (.fund, ["fund", "fondo", "sicav"]),
    ]

    /// The coin symbol for crypto instruments named in full.
    static let cryptoSymbols = ["bitcoin": "BTC", "ethereum": "ETH", "solana": "SOL", "cardano": "ADA"]

    /// Whether the header contains one of `phrases` as whole words.
    static func header(_ header: String?, has phrases: [String]) -> Bool {
        guard let header else { return false }
        return TextTools.contains(TextTools.words(header), anyOf: phrases)
    }

    /// The name a header stands for: without text in brackets, currency
    /// markers and value words. Falls back to the whole header.
    static func name(fromHeader header: String) -> String {
        var text = ""
        var depth = 0
        for character in header {
            if "([{".contains(character) { depth += 1; continue }
            if ")]}".contains(character) { depth = max(0, depth - 1); continue }
            if depth == 0 { text.append(character) }
        }
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var folded = words.map { TextTools.fold($0.trimmingCharacters(in: .punctuationCharacters)) }
        for phrase in headerNoise.sorted(by: { $0.count > $1.count }) {
            let parts = phrase.split(separator: " ").map(String.init)
            var index = 0
            while index + parts.count <= folded.count {
                if Array(folded[index..<(index + parts.count)]) == parts {
                    folded.removeSubrange(index..<(index + parts.count))
                    words.removeSubrange(index..<(index + parts.count))
                } else {
                    index += 1
                }
            }
        }
        let kept = zip(words, folded).filter { word, folded in
            !folded.isEmpty && CurrencyMarkers.currency(in: word) == nil
                && !CurrencyMarkers.codes.contains(folded.uppercased())
        }.map(\.0)
        let name = TextTools.trim(kept.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "-–:/")))
        return name.isEmpty ? TextTools.trim(header) : name
    }

    /// A currency pair named in a header: `EUR/USD`, `EURUSD`, `USD per EUR`.
    static func currencyPair(inHeader header: String) -> (base: CurrencyCode, quote: CurrencyCode)? {
        let tokens = header.uppercased().split { !$0.isLetter }.map(String.init)
        var codes: [String] = []
        var perIndex: Int?
        for token in tokens {
            if CurrencyMarkers.codes.contains(token) {
                codes.append(token)
            } else if token.count == 6, CurrencyMarkers.codes.contains(String(token.prefix(3))),
                      CurrencyMarkers.codes.contains(String(token.suffix(3))) {
                codes += [String(token.prefix(3)), String(token.suffix(3))]
            } else if token == "PER", codes.count == 1 {
                perIndex = 1
            }
        }
        guard codes.count == 2, codes[0] != codes[1] else { return nil }
        if perIndex != nil { return (CurrencyCode(codes[1]), CurrencyCode(codes[0])) }
        return (CurrencyCode(codes[0]), CurrencyCode(codes[1]))
    }
}
