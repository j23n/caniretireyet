import Foundation
import Model
import Prices
import Tracker

// The check-in's price list (UI.md, "Prices": the source and time of each
// price, and a way to type in any that failed), built from the draft and the
// latest fetch. Free of SwiftUI so it can be checked on Linux.

/// One line of the price list: an instrument's price, an exchange rate or an
/// inflation index, and where its value comes from.
struct CheckInPriceLine: Identifiable, Hashable, Sendable {
    /// Where the line's value stands.
    enum Status: Hashable, Sendable {
        /// Fetched for this check-in.
        case fetched
        /// Typed in by hand for this check-in.
        case typed
        /// Fetching failed (see ``CheckInPriceLine/failure``); it can be typed in.
        case failed
        /// The instrument has no price source, so its price is typed in.
        case manual
        /// Not fetched for this check-in (yet): the latest known value is used.
        case notFetched
    }

    var item: PriceListEntry.Item
    /// "VWCE", "USD", "Inflation (Italy)".
    var title: String
    /// The instrument's full name, or "1 EUR in US dollars".
    var subtitle: String?
    /// The value used: the check-in's own, else the latest known one.
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
    /// Whether it can be typed in here (instruments and rates; not indices).
    var canEnter: Bool

    var id: PriceListEntry.Item { item }

    /// Whether the line wants the user: it failed or has no price source,
    /// and nothing was typed in for this check-in.
    var needsAttention: Bool {
        status == .failed || (status == .manual && staleDate != nil) || (status == .manual && value == nil)
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

    /// The list for `draft`, with what the latest fetch (`fetched`) said
    /// about each item. Items are what the draft's rows hold (positions not
    /// sold) and the currencies they need, plus anything the fetch listed.
    /// `today` tells how far in the past the check-in is, for the reason a
    /// price failed.
    static func make(draft: CheckInDraft, fetched: CheckInPrices?, library: Library, today: CalendarDate = .today(),
                     locale: Locale = .current) -> CheckInPriceList {
        let fetched = fetched?.date == draft.date ? fetched : nil
        let base = library.settings.baseCurrency
        let priceTable = PriceTable(library: library)
        var fxLibrary = library
        for rate in draft.fxRates { fxLibrary.upsert(rate) }
        let fxTable = FXTable(library: fxLibrary)

        // Instruments.
        var instrumentIDs = Set(draft.rows.filter { $0.mode == .holdings }
            .flatMap { $0.positions.filter { $0.quantity != 0 }.map(\.instrument) })
        for entry in fetched?.entries ?? [] {
            if case .instrument(let id) = entry.item { instrumentIDs.insert(id) }
        }
        let instruments = instrumentIDs.map { id in
            instrumentLine(id, draft: draft, entry: fetched?.entry(for: .instrument(id)), library: library,
                           prices: priceTable, today: today, locale: locale)
        }.sorted { ($0.title.lowercased(), $0.item) < ($1.title.lowercased(), $1.item) }

        // Exchange rates against the base currency.
        var quotes = Set(draft.currencies(in: library))
        for entry in fetched?.entries ?? [] {
            if case .fx(let entryBase, let quote) = entry.item, entryBase == base { quotes.insert(quote) }
        }
        let rates = quotes.sorted().map { quote in
            rateLine(quote, base: base, draft: draft, entry: fetched?.entry(for: .fx(base: base, quote: quote)),
                     fx: fxTable, today: today, locale: locale)
        }

        // Inflation indices, only when the fetch listed them (months missing).
        let indices = (fetched?.entries ?? []).compactMap { entry -> CheckInPriceLine? in
            guard case .index(let index) = entry.item else { return nil }
            return indexLine(index, entry: entry, locale: locale)
        }

        let fetchedAt = (fetched?.entries ?? []).compactMap(\.details?.fetchedAt).max()
        return CheckInPriceList(date: draft.date, instruments: instruments, rates: rates, indices: indices,
                              fetchedAt: fetchedAt)
    }

    // MARK: Lines

    private static func instrumentLine(_ id: InstrumentID, draft: CheckInDraft, entry: PriceListEntry?,
                                       library: Library, prices: PriceTable, today: CalendarDate,
                                       locale: Locale) -> CheckInPriceLine {
        let instrument = library.instruments[id]
        let own = draft.prices.first { $0.instrument == id }
        let known = own ?? prices.latest(for: id, onOrBefore: draft.date)
        let status: CheckInPriceLine.Status
        if own?.source == .manual {
            status = .typed
        } else if let entry {
            switch entry.outcome {
            case .fetched: status = own == nil ? .notFetched : .fetched
            case .manual: status = .manual
            case .failed: status = .failed
            }
        } else if own != nil {
            status = .fetched
        } else if instrument?.priceSource == nil {
            status = .manual
        } else {
            status = .notFetched
        }
        let unit = CheckInWording.unit(of: instrument)
        var symbol = entry?.symbol ?? instrument?.priceSource?.symbol
        if let typed = symbol, let resolved = entry?.resolvedSymbol { symbol = "\(typed) → \(resolved)" }
        return CheckInPriceLine(
            item: .instrument(id), title: CheckInWording.instrumentLabel(id, instrument: instrument),
            subtitle: instrument.map(\.name).flatMap { $0 == CheckInWording.instrumentLabel(id, instrument: instrument) ? nil : $0 },
            value: known?.price, currency: known?.currency ?? instrument?.currency,
            per: unit.isEmpty ? nil : "per " + (unit == "sh" ? "share" : unit),
            staleDate: known.flatMap { $0.date < draft.date ? $0.date : nil },
            status: status,
            source: sourceText(status == .typed ? .manual : (entry?.source ?? own?.source), symbol: status == .typed ? nil : symbol),
            observed: status == .fetched ? observedText(entry?.details, locale: locale) : nil,
            failure: status == .typed ? nil : failureText(entry, date: draft.date, today: today),
            canEnter: true)
    }

    private static func rateLine(_ quote: CurrencyCode, base: CurrencyCode, draft: CheckInDraft,
                                 entry: PriceListEntry?, fx: FXTable, today: CalendarDate,
                                 locale: Locale) -> CheckInPriceLine {
        let own = draft.fxRates.first { $0.base == base && $0.quote == quote }
        let known = fx.quote(from: base, to: quote, on: draft.date)
        let status: CheckInPriceLine.Status
        if own?.source == .manual {
            status = .typed
        } else if let entry {
            switch entry.outcome {
            case .fetched: status = own == nil ? .notFetched : .fetched
            case .manual: status = .manual
            case .failed: status = .failed
            }
        } else {
            status = own == nil ? .notFetched : .fetched
        }
        let name = locale.localizedString(forCurrencyCode: quote.rawValue)
        let knownDate = own?.date ?? known?.date
        return CheckInPriceLine(
            item: .fx(base: base, quote: quote), title: quote.rawValue,
            subtitle: name.map { "1 \(base.rawValue) in \($0)" },
            value: own?.rate ?? known?.rate, currency: nil, per: "\(quote.rawValue) per \(base.rawValue)",
            staleDate: knownDate.flatMap { $0 < draft.date ? $0 : nil },
            status: status,
            source: sourceText(status == .typed ? .manual : (entry?.source ?? own?.source),
                               symbol: status == .typed ? nil : entry?.symbol),
            observed: status == .fetched ? observedText(entry?.details, locale: locale) : nil,
            failure: status == .typed ? nil : failureText(entry, date: draft.date, today: today),
            canEnter: true)
    }

    private static func indexLine(_ index: IndexID, entry: PriceListEntry, locale: Locale) -> CheckInPriceLine {
        let status: CheckInPriceLine.Status = switch entry.outcome {
        case .fetched: .fetched
        case .manual: .manual
        case .failed: .failed
        }
        return CheckInPriceLine(
            item: .index(index), title: index == .hicpIT ? "Inflation (Italy)" : index.rawValue,
            subtitle: "Consumer prices, for plans in today's money", value: nil, currency: nil, per: nil,
            staleDate: nil, status: status, source: sourceText(entry.source, symbol: nil),
            observed: observedText(entry.details, locale: locale), failure: entry.failureReason, canEnter: false)
    }

    // MARK: Words

    /// How long CoinGecko's free API keeps daily prices: about a year.
    static let coinGeckoHistoryDays = 365

    /// Why an entry failed, for a check-in on `date`. A provider without
    /// history for the date (gold-api.com only has today's price; CoinGecko's
    /// free API about the last year) says so first: "No history for this
    /// date: type the price." `nil` unless the entry failed.
    static func failureText(_ entry: PriceListEntry?, date: CalendarDate, today: CalendarDate = .today()) -> String? {
        guard let entry, let error = entry.failure else { return nil }
        switch error {
        case .unsupportedDate:
            return noHistory + " " + error.description
        case .unauthorized where entry.source == .coingecko && date < today.adding(days: -coinGeckoHistoryDays):
            return noHistory + " CoinGecko's free prices only go back about a year."
        default:
            return error.description
        }
    }

    /// The start of the reason for a price that has no history for a past date.
    static let noHistory = "No history for this date: type the price."

    /// A source's name: "Yahoo Finance", "ECB", "Typed in".
    static func sourceName(_ source: DataSource) -> String {
        switch source {
        case .manual: "Typed in"
        case .yahoo: "Yahoo Finance"
        case .coingecko: "CoinGecko"
        case .goldAPI: "gold-api.com"
        case .ecb: "ECB"
        case .eurostat: "Eurostat"
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

/// The price status row at the top of the check-in: "Prices and FX updated
/// (4)", "2 couldn't be fetched", "Fetching prices…".
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
        // A provider without history for a past date isn't a failure to retry: the price is typed in.
        let noHistory = lines.count { $0.status == .failed && $0.failure?.hasPrefix(CheckInPriceList.noHistory) == true }
        let failed = lines.count { $0.status == .failed } - noHistory
        let noSource = lines.count { $0.status == .manual && $0.needsAttention }
        if failed > 0 {
            return CheckInPriceStatus(
                kind: .needsAttention,
                title: failed == 1 ? "1 price couldn't be fetched" : "\(failed) prices couldn't be fetched",
                subtitle: "The latest known ones are used · tap to type them in")
        }
        let toType = noSource + noHistory
        if toType > 0 {
            let reason = switch (noSource > 0, noHistory > 0) {
            case (true, true): "No price source, or no history for this date"
            case (false, true): "No history for this date"
            default: "No price source"
            }
            return CheckInPriceStatus(
                kind: .needsAttention, title: toType == 1 ? "1 price to type in" : "\(toType) prices to type in",
                subtitle: reason + " · tap to enter")
        }
        if lines.contains(where: { $0.status == .notFetched }) {
            return CheckInPriceStatus(kind: .notFetched, title: "\(noun) not fetched",
                                      subtitle: "The latest known ones are used · tap to fetch or type them")
        }
        let time = list.fetchedAt.map { " · " + CheckInPriceList.time($0, locale: locale) } ?? ""
        return CheckInPriceStatus(kind: .updated, title: "\(noun) updated (\(lines.count))", subtitle: names + time)
    }
}
