import Foundation
import Model

/// FX rates by currency pair, for converting amounts at the latest rate on
/// or before a date.
///
/// Records follow the ECB convention (1 base = rate × quote). A conversion
/// uses a direct rate, an inverse rate, or two legs crossed via a pivot
/// currency: the preferred pivots first (normally the library's base
/// currency), then any other currency with rates.
public struct FXTable: Sendable {
    private struct Pair: Hashable {
        var base: CurrencyCode
        var quote: CurrencyCode
    }

    private let byPair: [Pair: [FXRecord]]
    private let pivots: [CurrencyCode]

    /// Indexes FX records. For duplicate keys the last record wins. Records
    /// with a rate of zero or less (a typo in a hand-edited file) are
    /// ignored: converting with them would divide by zero.
    public init(_ records: some Sequence<FXRecord>, pivots: [CurrencyCode] = []) {
        var byKey: [FXKey: FXRecord] = [:]
        for record in records where record.rate > 0 { byKey[record.key] = record }
        let byPair = Dictionary(grouping: byKey.values) { Pair(base: $0.base, quote: $0.quote) }
            .mapValues { $0.sortedByKey() }
        self.byPair = byPair
        let others = Set(byPair.keys.flatMap { [$0.base, $0.quote] }).subtracting(pivots).sorted()
        var seen: Set<CurrencyCode> = []
        self.pivots = (pivots + others).filter { seen.insert($0).inserted }
    }

    /// Indexes every FX rate in the library, pivoting via its base currency first.
    public init(library: Library) {
        self.init(library.months.values.lazy.flatMap(\.fx), pivots: [library.settings.baseCurrency])
    }

    /// How to convert from one currency to another on `date`, or `nil` if no
    /// rate (direct, inverse or crossed) is recorded on or before it.
    public func quote(from: CurrencyCode, to: CurrencyCode, on date: CalendarDate) -> FXQuote? {
        if from == to { return FXQuote(from: from, to: to, legs: []) }
        if let leg = leg(from: from, to: to, on: date) {
            return FXQuote(from: from, to: to, legs: [leg])
        }
        for pivot in pivots where pivot != from && pivot != to {
            if let first = leg(from: from, to: pivot, on: date), let second = leg(from: pivot, to: to, on: date) {
                return FXQuote(from: from, to: to, legs: [first, second])
            }
        }
        return nil
    }

    /// `amount` in `from` converted to `to` on `date`, or `nil` without a rate.
    public func convert(_ amount: Decimal, from: CurrencyCode, to: CurrencyCode, on date: CalendarDate) -> Decimal? {
        quote(from: from, to: to, on: date)?.convert(amount)
    }

    /// One leg: the more recent of the direct and the inverse rate (direct on a tie).
    private func leg(from: CurrencyCode, to: CurrencyCode, on date: CalendarDate) -> FXQuote.Leg? {
        let direct = latest(Pair(base: from, quote: to), on: date)
        let inverse = latest(Pair(base: to, quote: from), on: date)
        switch (direct, inverse) {
        case (let direct?, let inverse?):
            return inverse.date > direct.date ? FXQuote.Leg(record: inverse, inverted: true)
                                              : FXQuote.Leg(record: direct, inverted: false)
        case (let direct?, nil): return FXQuote.Leg(record: direct, inverted: false)
        case (nil, let inverse?): return FXQuote.Leg(record: inverse, inverted: true)
        case (nil, nil): return nil
        }
    }

    private func latest(_ pair: Pair, on date: CalendarDate) -> FXRecord? {
        guard let records = byPair[pair], let index = records.lastIndex(onOrBefore: date, date: \.date) else {
            return nil
        }
        return records[index]
    }
}

/// A conversion from one currency to another, and the recorded rates it uses.
public struct FXQuote: Hashable, Sendable {
    /// One recorded rate, used as written or inverted.
    public struct Leg: Hashable, Sendable {
        public let record: FXRecord
        /// Whether the conversion goes from the record's quote to its base.
        public let inverted: Bool

        /// Converts along this leg: × rate, or ÷ rate when inverted.
        public func convert(_ amount: Decimal) -> Decimal {
            inverted ? amount / record.rate : amount * record.rate
        }
    }

    public let from: CurrencyCode
    public let to: CurrencyCode
    /// The rates used, in order: none for the identity, one direct or
    /// inverted rate, or two crossed via a pivot currency.
    public let legs: [Leg]

    /// The rate such that 1 `from` = `rate` × `to`.
    public var rate: Decimal {
        convert(1)
    }

    /// The date of the oldest rate used, or `nil` for the identity.
    public var date: CalendarDate? {
        legs.map(\.record.date).min()
    }

    /// Converts `amount` from `from` to `to`, leg by leg.
    public func convert(_ amount: Decimal) -> Decimal {
        legs.reduce(amount) { $1.convert($0) }
    }
}
