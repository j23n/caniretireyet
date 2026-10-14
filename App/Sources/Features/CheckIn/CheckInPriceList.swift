import Foundation
import Model
import Prices
import Tracker

// The check-in's price list (UI.md, "Prices": the source and time of each
// price, and why any failed), built from the library and the latest fetch.
// Free of SwiftUI so it can be checked on Linux.

/// One line of the price list: an instrument's price, an exchange rate or an
/// inflation index, and where its value comes from.
struct CheckInPriceLine: Identifiable, Hashable, Sendable {
    /// Where the line's value stands.
    enum Status: Hashable, Sendable {
        /// Fetched for this check-in.
        case fetched
        /// Fetching failed (see ``CheckInPriceLine/failure``).
        case failed
        /// The instrument has no price source: its price is set on the
        /// Instruments screen.
        case manual
        /// Not fetched for this check-in (yet): the latest known value is used.
        case notFetched
    }

    var item: PriceListEntry.Item
    /// "VWCE", "USD", "Inflation (Germany)".
    var title: String
    /// The instrument's full name, or "1 EUR in US dollars".
    var subtitle: String?
    /// The value used: the one fetched for the check-in, else the latest known one.
    var value: Decimal?
    /// The currency of ``value`` for a price; `nil` for rates and indices.
    var currency: CurrencyCode?
    /// "per share", "per g", "USD per EUR".
    var per: String?
    /// The date of ``value`` when it's older than the check-in ("from 31 Aug").
    var staleDate: CalendarDate?
    var status: Status
    /// "Yahoo Finance · VWCE.DE".
    var source: String?
    /// "As of 26 Sep · fetched 09:41".
    var observed: String?
    /// Why fetching failed.
    var failure: String?

    var id: PriceListEntry.Item { item }

    /// Whether the line wants the user: it failed, or it has no price source
    /// and no price for the date.
    var needsAttention: Bool {
        status == .failed || (status == .manual && (staleDate != nil || value == nil))
    }
}

/// Every price, rate and index the check-in uses, in three sections.
struct CheckInPriceList: Hashable, Sendable {
    var date: CalendarDate
    var instruments: [CheckInPriceLine]
    var rates: [CheckInPriceLine]
    var indices: [CheckInPriceLine]
    /// When the latest value was fetched.
    var fetchedAt: Date?

    var lines: [CheckInPriceLine] { instruments + rates + indices }
    var isEmpty: Bool { lines.isEmpty }

    /// The list for a check-in on `date`, with what the latest fetch
    /// (`fetched`) said about each item. Items are what the library's open
    /// accounts hold on the date and the currencies they need
    /// (`CheckInPriceNeeds`), plus anything the fetch listed.
    static func make(date: CalendarDate, fetched: CheckInPrices?, library: Library,
                     locale: Locale = .current) -> CheckInPriceList {
        let fetched = fetched?.date == date ? fetched : nil
        let needs = CheckInPriceNeeds(library: library, date: date, indices: [])
        let base = needs.baseCurrency
        let priceTable = PriceTable(library: library)
        let fxTable = FXTable(library: library)

        var instrumentIDs = Set(needs.instruments.map(\.id) + needs.manualInstruments)
        var quotes = Set(needs.currencies)
        for entry in fetched?.entries ?? [] {
            switch entry.item {
            case .instrument(let id): instrumentIDs.insert(id)
            case .fx(let entryBase, let quote) where entryBase == base: quotes.insert(quote)
            default: break
            }
        }
        let instruments = instrumentIDs.map { id in
            instrumentLine(id, date: date, fetched: fetched, library: library, prices: priceTable, locale: locale)
        }.sorted { ($0.title.lowercased(), $0.item) < ($1.title.lowercased(), $1.item) }
        let rates = quotes.sorted().map { quote in
            rateLine(quote, base: base, date: date, fetched: fetched, fx: fxTable, locale: locale)
        }
        // Inflation indices, only when the fetch listed them (months missing).
        let indices = (fetched?.entries ?? []).compactMap { entry -> CheckInPriceLine? in
            guard case .index(let index) = entry.item else { return nil }
            return indexLine(index, entry: entry, locale: locale)
        }
        let fetchedAt = (fetched?.entries ?? []).compactMap(\.details?.fetchedAt).max()
        return CheckInPriceList(date: date, instruments: instruments, rates: rates, indices: indices,
                                fetchedAt: fetchedAt)
    }

    // MARK: Lines

    private static func instrumentLine(_ id: InstrumentID, date: CalendarDate, fetched: CheckInPrices?,
                                       library: Library, prices: PriceTable, locale: Locale) -> CheckInPriceLine {
        let instrument = library.instruments[id]
        let entry = fetched?.entry(for: .instrument(id))
        let own = fetched?.prices.first { $0.instrument == id }
        let known = own ?? prices.latest(for: id, onOrBefore: date)
        let status = lineStatus(hasOwn: own != nil, entry: entry,
                                otherwise: instrument?.priceSource == nil ? .manual : .notFetched)
        let unit = CheckInWording.unit(of: instrument)
        let label = CheckInWording.instrumentLabel(id, instrument: instrument)
        var symbol = entry?.symbol ?? instrument?.priceSource?.symbol
        if let typed = symbol, let resolved = entry?.resolvedSymbol { symbol = "\(typed) → \(resolved)" }
        // A stand-in for a date the source has no price for: "Yahoo Finance · GC=F (history)".
        if let shown = symbol, let note = entry?.note { symbol = "\(shown) (\(note))" }
        return CheckInPriceLine(
            item: .instrument(id), title: label,
            subtitle: instrument.map(\.name).flatMap { $0 == label ? nil : $0 },
            value: known?.price, currency: known?.currency ?? instrument?.currency,
            per: unit.isEmpty ? nil : "per " + (unit == "sh" ? "share" : unit),
            staleDate: known.flatMap { $0.date < date ? $0.date : nil },
            status: status, source: sourceText(entry?.source ?? known?.source, symbol: symbol),
            observed: status == .fetched ? observedText(entry?.details, locale: locale) : nil,
            failure: entry?.failure?.description)
    }

    private static func rateLine(_ quote: CurrencyCode, base: CurrencyCode, date: CalendarDate,
                                 fetched: CheckInPrices?, fx: FXTable, locale: Locale) -> CheckInPriceLine {
        let entry = fetched?.entry(for: .fx(base: base, quote: quote))
        let own = fetched?.fx.first { $0.base == base && $0.quote == quote }
        let known = fx.quote(from: base, to: quote, on: date)
        let status = lineStatus(hasOwn: own != nil, entry: entry, otherwise: .notFetched)
        let name = locale.localizedString(forCurrencyCode: quote.rawValue)
        let knownDate = own?.date ?? known?.date
        return CheckInPriceLine(
            item: .fx(base: base, quote: quote), title: quote.rawValue,
            subtitle: name.map { "1 \(base.rawValue) in \($0)" },
            value: own?.rate ?? known?.rate, currency: nil, per: "\(quote.rawValue) per \(base.rawValue)",
            staleDate: knownDate.flatMap { $0 < date ? $0 : nil },
            status: status, source: sourceText(entry?.source ?? own?.source, symbol: entry?.symbol),
            observed: status == .fetched ? observedText(entry?.details, locale: locale) : nil,
            failure: entry?.failure?.description)
    }

    private static func indexLine(_ index: IndexID, entry: PriceListEntry, locale: Locale) -> CheckInPriceLine {
        // The values fetched are the check-in's own: they're saved with it.
        let status = lineStatus(hasOwn: true, entry: entry, otherwise: .notFetched)
        return CheckInPriceLine(
            item: .index(index), title: InflationIndexText.title(of: index, locale: locale),
            subtitle: "Consumer prices, for plans in today's money", value: nil, currency: nil, per: nil,
            staleDate: nil, status: status, source: sourceText(entry.source, symbol: nil),
            observed: observedText(entry.details, locale: locale), failure: entry.failureReason)
    }

    /// Where a line stands: as the fetch left it, fetched only once the
    /// check-in has the value (`hasOwn`); without an entry, fetched when it
    /// has one, else `otherwise`.
    private static func lineStatus(hasOwn: Bool, entry: PriceListEntry?,
                                   otherwise: CheckInPriceLine.Status) -> CheckInPriceLine.Status {
        guard let entry else { return hasOwn ? .fetched : otherwise }
        switch entry.outcome {
        case .fetched: return hasOwn ? .fetched : .notFetched
        case .manual: return .manual
        case .failed: return .failed
        }
    }

    // MARK: Words

    /// A source's name: "Yahoo Finance", "ECB", "Typed in".
    static func sourceName(_ source: DataSource) -> String {
        switch source {
        case .manual: "Typed in"
        case .yahoo: "Yahoo Finance"
        case .coingecko: "CoinGecko"
        case .goldAPI: "gold-api.com"
        case .ecb: "ECB"
        case .eurostat: "Eurostat"
        case .bls: "BLS"
        case .ons: "ONS"
        case .import: "Imported"
        default: source.rawValue
        }
    }

    /// "Yahoo Finance · VWCE.DE".
    static func sourceText(_ source: DataSource?, symbol: String?) -> String? {
        let parts = [source.map(sourceName), symbol].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "As of 26 Sep · fetched 09:41".
    static func observedText(_ details: FetchDetails?, locale: Locale = .current) -> String? {
        guard let details else { return nil }
        var parts: [String] = []
        if let observed = details.observedOn {
            parts.append("As of " + AmountFormat.shortDate(observed, locale: locale))
        }
        parts.append((parts.isEmpty ? "Fetched " : "fetched ") + time(details.fetchedAt, locale: locale))
        return parts.joined(separator: " · ")
    }

    /// "09:41" today, "29 Sep, 09:41" on another day.
    static func time(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(.dateTime.hour().minute().locale(locale))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }
}

/// The price status row on the check-in: "Prices and FX updated (4)",
/// "2 couldn't be fetched", "Fetching prices…".
struct CheckInPriceStatus: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case fetching
        case updated
        case needsAttention
        case notFetched
    }

    var kind: Kind
    var title: String
    var subtitle: String?

    /// The summary for the list; `nil` when the check-in needs no prices at
    /// all (only balances in the base currency) and nothing is being fetched.
    static func make(_ list: CheckInPriceList, isFetching: Bool, locale: Locale = .current) -> CheckInPriceStatus? {
        let lines = list.lines
        guard !lines.isEmpty || isFetching else { return nil }
        let names = lines.map(\.title).joined(separator: ", ")
        let noun = list.rates.isEmpty ? "Prices" : "Prices and FX"
        if isFetching {
            return CheckInPriceStatus(kind: .fetching, title: "Fetching \(noun.lowercased())…",
                                      subtitle: names.isEmpty ? nil : names)
        }
        let failed = lines.count { $0.status == .failed }
        if failed > 0 {
            return CheckInPriceStatus(
                kind: .needsAttention,
                title: failed == 1 ? "1 price couldn't be fetched" : "\(failed) prices couldn't be fetched",
                subtitle: "The latest known ones are used")
        }
        let noSource = lines.count { $0.status == .manual && $0.needsAttention }
        if noSource > 0 {
            return CheckInPriceStatus(
                kind: .needsAttention,
                title: noSource == 1 ? "1 price without a source" : "\(noSource) prices without a source",
                subtitle: "The latest known ones are used · set them on the Instruments screen")
        }
        if lines.contains(where: { $0.status == .notFetched }) {
            return CheckInPriceStatus(kind: .notFetched, title: "\(noun) not fetched",
                                      subtitle: "The latest known ones are used")
        }
        let time = list.fetchedAt.map { " · " + CheckInPriceList.time($0, locale: locale) } ?? ""
        return CheckInPriceStatus(kind: .updated, title: "\(noun) updated (\(lines.count))", subtitle: names + time)
    }
}
