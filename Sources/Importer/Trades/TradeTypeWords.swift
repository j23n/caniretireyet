import Foundation
import Model

/// The words a trades file's settlement column is read with (IMPORT.md,
/// "Columns"): whether a buy, sell, fee or tax was paid from or into
/// another account. Compared ignoring case and accents.
public enum SettlementWords {
    /// Paid from or into another account.
    static let external = ["external", "outside", "esterno", "esterna", "fuori", "yes", "y", "si", "true", "x", "1"]
    /// The account's own cash.
    static let account = ["account", "internal", "interno", "conto", "no", "n", "false", "0"]

    /// The settlement `text` says; `nil` when it says neither.
    public static func settlement(for text: String) -> TradeSettlement? {
        let folded = TextTools.fold(text)
        if external.contains(folded) { return .external }
        if account.contains(folded) { return .account }
        return nil
    }
}

/// The words brokers use for trade types, in Italian and English, and how a
/// file's word is read as a trade type (IMPORT.md, "Broker transactions").
///
/// A profile's `tradeTypes` map comes first. Otherwise the default words
/// suggest a type: the whole value (`Acquisto`, `Compravendita acquisto`,
/// `Buy`), else the default words it contains, as long as they all point
/// to one type (`Ritenuta su dividendo`: a tax, as a charge wins over the
/// income it's taken from). Anything else is unmapped: its rows are flagged
/// and left out, never guessed.
public enum TradeTypeWords {
    /// The value of a `tradeTypes` entry that leaves the rows of that type out.
    public static let ignore: TradeType = "ignore"

    /// The default words for each type, folded (lowercase, no accents),
    /// words separated by single spaces.
    public static let defaults: [(type: TradeType, phrases: [String])] = [
        (.buy, ["acquisto", "acquisti", "compravendita acquisto", "acquisto titoli", "sottoscrizione", "buy",
                "bought", "purchase"]),
        (.sell, ["vendita", "vendite", "compravendita vendita", "vendita titoli", "sell", "sold", "sale"]),
        (.dividend, ["dividendo", "dividendi", "cedola", "cedole", "dividend", "dividends", "coupon", "coupons",
                     "distribuzione", "distribution"]),
        (.interest, ["interessi", "interesse", "interessi attivi", "interessi creditori", "interest"]),
        (.fee, ["commissioni", "commissione", "spese", "fee", "fees", "commission", "commissions"]),
        (.tax, ["bollo", "imposta", "imposte", "imposta di bollo", "ritenuta", "ritenute", "tassa", "tasse", "tax",
                "taxes", "withholding tax", "tobin tax", "ftt"]),
        (.deposit, ["versamento", "versamenti", "bonifico in entrata", "deposit", "deposits",
                    "deposits withdrawals"]),
        (.withdrawal, ["prelievo", "prelevamento", "bonifico in uscita", "withdrawal", "withdrawals"]),
        (.split, ["frazionamento", "raggruppamento", "split", "reverse split", "stock split"]),
    ]

    /// The type a file's word suggests, or `nil` when it suggests none or
    /// several: first the whole value, then the words in it.
    public static func suggestion(for value: String) -> TradeType? {
        let words = TextTools.words(value)
        guard !words.isEmpty else { return nil }
        let whole = words.joined(separator: " ")
        if let exact = defaults.first(where: { $0.phrases.contains(whole) }) { return exact.type }
        let found = Set(defaults.filter { TextTools.contains(words, anyOf: $0.phrases) }.map(\.type))
        if found.count == 1 { return found.first }
        // A charge on something else: "Ritenuta su dividendo", "Commissioni su vendita".
        let charges = found.intersection([.tax, .fee])
        return charges.count == 1 ? charges.first : nil
    }

    /// A value's entry in a profile's map: exactly, then ignoring case and accents.
    static func lookup(_ value: String, in map: [String: TradeType]) -> TradeType? {
        if let type = map[value] { return type }
        let folded = TextTools.fold(value)
        return map.keys.sorted().first { TextTools.fold($0) == folded }.flatMap { map[$0] }
    }

    /// The types a type column can be mapped to, in menu order.
    public static let choices: [TradeType] = [
        .buy, .sell, .dividend, .interest, .fee, .tax, .deposit, .withdrawal, .split, .transferIn, .transferOut,
        .opening,
    ]
}

/// One of the values of a trades file's type column, and the trade type
/// it's read as (the Types step; `retire import`'s "Types").
public struct TradeTypeValue: Hashable, Sendable, Identifiable {
    /// Where the mapping comes from.
    public enum Source: String, Hashable, Sendable {
        /// The profile's `tradeTypes`.
        case profile
        /// The default words.
        case suggested
        /// Nothing: its rows are left out and flagged.
        case unmapped
    }

    /// The value as the file writes it (its first spelling).
    public var value: String
    public var id: String { value }
    /// How many rows have it.
    public var count: Int
    /// The type its rows become; ``TradeTypeWords/ignore`` leaves them out;
    /// `nil` when unmapped.
    public var type: TradeType?
    public var source: Source
    /// What the default words suggest, if anything.
    public var suggestion: TradeType?

    public init(value: String, count: Int, type: TradeType?, source: Source, suggestion: TradeType?) {
        self.value = value
        self.count = count
        self.type = type
        self.source = source
        self.suggestion = suggestion
    }

    /// Whether its rows are left out on purpose (`ignore`).
    public var isIgnored: Bool { type == TradeTypeWords.ignore }

    /// Whether its rows become trades.
    public var isImported: Bool { type != nil && !isIgnored }
}
