import Foundation
import Model
import Prices
import Tracker

// An instrument's prices outside a check-in (UI.md, "Instruments"): how the
// latest saved price reads in lists, a price typed in by hand (*Set
// Price…*), and a *Test price fetch* result that can be saved. Free of
// SwiftUI so it can be checked on Linux.

/// How an instrument's details read in lists.
enum InstrumentText {
    /// "IE00BK5BQT80 · VWCE", or "–".
    static func identifiers(of instrument: Instrument) -> String {
        let parts = [instrument.isin, instrument.ticker].compactMap { $0 }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    /// "EUR per share".
    static func pricedIn(_ instrument: Instrument) -> String {
        "\(instrument.currency) per \(InstrumentForm.name(of: instrument.unit))"
    }

    /// "Yahoo Finance (unofficial) · VWCE.DE", or "Typed in by hand".
    static func source(of instrument: Instrument) -> String {
        sourceText(of: instrument) ?? "Typed in by hand"
    }

    /// "Yahoo Finance (unofficial) · VWCE.DE"; `nil` without a price source.
    static func sourceText(of instrument: Instrument) -> String? {
        guard let source = instrument.priceSource else { return nil }
        return "\(InstrumentForm.name(of: source.provider)) · \(source.symbol)"
    }

    /// "138,42 €", "0,004312 €" (``QuantityFormat/unitPrice(_:currency:locale:)``);
    /// the number alone without a currency.
    static func price(_ value: Decimal, currency: CurrencyCode?, locale: Locale = .current) -> String {
        guard let currency else { return QuantityFormat.unitPriceNumber(value, locale: locale) }
        return QuantityFormat.unitPrice(value, currency: currency, locale: locale)
    }
}

/// An instrument's latest saved price, as the Instruments list shows it:
/// "138,42 € on 30 Sep", marked when it's older than the staleness
/// threshold (the one accounts use).
struct InstrumentLatestPrice: Hashable, Sendable {
    var record: PriceRecord
    /// Whether it's older than the staleness threshold.
    var isStale: Bool
    /// Whether it was typed in by hand (or imported) although the instrument
    /// has a price source.
    var isNotFetched: Bool

    /// The latest price on or before `today`; `nil` if there's none.
    init?(of instrument: Instrument, prices: PriceTable, today: CalendarDate, stalenessThreshold: Int) {
        guard let record = prices.latest(for: instrument.id, onOrBefore: today) else { return nil }
        self.record = record
        isStale = record.date.days(to: today) > stalenessThreshold
        isNotFetched = instrument.priceSource != nil && (record.source == .manual || record.source == .import)
    }

    /// "138,42 € on 30 Sep".
    func text(locale: Locale = .current) -> String {
        InstrumentText.price(record.price, currency: record.currency, locale: locale) + " on "
            + AmountFormat.shortDate(record.date, locale: locale)
    }

    /// "typed in" or "imported" when that's where the price came from
    /// although the instrument has a price source.
    var sourceNote: String? {
        guard isNotFetched else { return nil }
        return record.source == .manual ? "typed in" : "imported"
    }

    /// "Older than 45 days" for the stale mark's help and VoiceOver.
    static func staleHelp(threshold: Int) -> String {
        "Older than \(threshold) days"
    }
}

/// A price typed in by hand (*Set Price…*): the date (today by default),
/// the amount, and its currency (the instrument's by default). It's saved
/// as a `manual` price record, replacing any price saved for that date, and
/// *Update Prices* keeps it.
struct InstrumentPriceForm: Hashable, Sendable {
    var date: CalendarDate
    /// As typed; read with `AmountInput`.
    var amount = ""
    var currency: CurrencyCode

    init(currency: CurrencyCode, date: CalendarDate = .today()) {
        self.date = date
        self.currency = currency
    }

    /// The date for a date picker: noon on ``date`` in the device's time zone.
    var pickedDate: Date {
        get { date.dateValue }
        set { date = CalendarDate(newValue, in: .current) }
    }

    /// The typed amount, if it reads as a number.
    func price(locale: Locale = .current) -> Decimal? {
        AmountInput.decimal(from: amount, locale: locale)
    }

    /// What must be fixed before saving, in order.
    func problems(today: CalendarDate = .today(), locale: Locale = .current) -> [String] {
        var problems: [String] = []
        if amount.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Enter the price.")
        } else if let price = price(locale: locale) {
            if price <= 0 { problems.append("A price is more than zero.") }
        } else {
            problems.append("The price isn't a number.")
        }
        if date > today { problems.append("Choose today or an earlier date.") }
        if !currency.isWellFormed { problems.append("Choose the currency of the price.") }
        return problems
    }

    /// The price record for `instrument`; `nil` while there are problems.
    func record(for instrument: InstrumentID, today: CalendarDate = .today(),
                locale: Locale = .current) -> PriceRecord? {
        guard problems(today: today, locale: locale).isEmpty, let price = price(locale: locale) else { return nil }
        return PriceRecord(instrument: instrument, date: date, price: price, currency: currency, source: .manual)
    }

    /// "Replaces 138,42 € from Yahoo Finance saved for 30 Sep."; `nil`
    /// when nothing is saved for the date.
    static func replacementNote(_ existing: PriceRecord?, locale: Locale = .current) -> String? {
        guard let existing else { return nil }
        var text = "Replaces " + InstrumentText.price(existing.price, currency: existing.currency, locale: locale)
        if let source = existing.source {
            text += source == .manual ? " typed in" : " from " + CheckInPriceList.sourceName(source)
        }
        return text + " for " + AmountFormat.shortDate(existing.date, locale: locale) + "."
    }
}

/// A *Test price fetch* result that can be saved: the fetched price and
/// rates, for the instrument as it was when tested (currency, unit, price
/// source). Saving follows *Update Prices*' rule: a price or rate typed in
/// by hand for the same date is kept unless you choose to replace it.
struct InstrumentTestQuote: Hashable, Sendable {
    var fetched: CheckInPrices
    var entry: PriceListEntry
    var currency: CurrencyCode
    var unit: InstrumentUnit
    var priceSource: PriceSource?
    /// Whether it has been saved.
    var isSaved = false

    init(_ fetched: CheckInPrices, for instrument: Instrument) {
        self.fetched = fetched
        entry = fetched.entry(for: .instrument(instrument.id))
            ?? PriceListEntry(item: .instrument(instrument.id), outcome: .manual)
        currency = instrument.currency
        unit = instrument.unit
        priceSource = instrument.priceSource
    }

    /// The fetched price; `nil` if the fetch failed.
    var price: PriceRecord? {
        guard entry.details != nil, case .instrument(let id) = entry.item else { return nil }
        return fetched.prices.first { $0.instrument == id }
    }

    /// Whether the price still fits `instrument`: the same currency, unit
    /// and price source as when it was tested.
    func fits(_ instrument: Instrument) -> Bool {
        instrument.currency == currency && instrument.unit == unit && instrument.priceSource == priceSource
    }

    /// The price typed in by hand for the price's date that saving would
    /// replace, if any.
    func typedPrice(for id: InstrumentID, in library: Library) -> PriceRecord? {
        guard let price, let saved = library.price(PriceKey(instrument: id, date: price.date)),
              saved.source == .manual else {
            return nil
        }
        return saved
    }

    /// What saving it for the instrument `id` writes: the price (unless one
    /// typed in by hand for the date is kept) and the rates (except those
    /// typed in by hand for the date).
    func records(for id: InstrumentID, in library: Library,
                 replacingTyped: Bool = false) -> InstrumentPriceUpdate.Records {
        var records = InstrumentPriceUpdate.Records()
        if var price, replacingTyped || typedPrice(for: id, in: library) == nil {
            price.instrument = id
            records.prices = [price]
        }
        records.fxRates = fetched.fx.filter {
            library.fxRate($0.key)?.source != .manual
        }
        return records
    }

    /// The result as a sentence, with "ETH → ethereum · " in front when the
    /// provider knows the symbol by another ID.
    func describe(canFetch: Bool, locale: Locale = .current) -> String {
        let text = InstrumentForm.describe(entry, canFetch: canFetch, locale: locale)
        guard let symbol = entry.symbol, let resolved = entry.resolvedSymbol, entry.details != nil else {
            return text
        }
        return "\(symbol) → \(resolved) · " + text
    }
}
