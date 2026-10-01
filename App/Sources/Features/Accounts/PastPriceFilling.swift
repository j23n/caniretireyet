import Foundation
import Model
import Observation
import Prices
import Tracker

// *Fill In Past Prices* (UI.md, "Instruments" and "Adding history"): what the
// library is missing on past dates, fetched a range per instrument at a time
// (`PriceService.fillPastPrices`) and saved in one edit that replaces nothing.
// Free of SwiftUI so it can be checked on Linux.

/// One line of *Fill In Past Prices*: an instrument, an exchange rate or an
/// index, the dates it needs a value on, and, after a fill, what happened.
struct PastPriceLine: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// An instrument with a price source: fetched.
        case fetched
        /// An instrument without one: typed in, or given a source.
        case manual
        /// A position whose instrument isn't in the library.
        case unknown
        /// An exchange rate against the base currency.
        case rate
        /// An inflation index.
        case index
    }

    var item: PriceListEntry.Item
    var kind: Kind
    /// The instrument's name, "USD", "Inflation (Italy)".
    var title: String
    /// Where it's fetched from, before a fill: "gold-api.com · XAU".
    var source: String?
    /// The dates it needs a value on, sorted.
    var dates: [CalendarDate]
    /// What the fill did, once it ran.
    var result: PastPriceResult?

    var id: PriceListEntry.Item { item }

    var instrument: InstrumentID? {
        if case .instrument(let id) = item { id } else { nil }
    }

    /// The dates still without a value: all of them before a fill.
    var missing: [CalendarDate] { result?.missing ?? dates }

    /// Whether it's an instrument whose missing prices can be typed in.
    var canBeTypedIn: Bool { instrument != nil && kind != .unknown }
}

/// What *Fill In Past Prices* will fetch, and what has to be typed in.
struct PastPricePlan: Hashable, Sendable {
    var needs: PastPriceNeeds
    /// Fetched instruments, then rates, then indices, then instruments
    /// typed in and unknown ones.
    var lines: [PastPriceLine]

    init(needs: PastPriceNeeds, library: Library) {
        self.needs = needs
        func name(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }
        let byName: (PastPriceNeeds.InstrumentDates, PastPriceNeeds.InstrumentDates) -> Bool = {
            (name($0.instrument).lowercased(), $0.instrument) < (name($1.instrument).lowercased(), $1.instrument)
        }
        var lines = needs.instruments.sorted(by: byName).map { need in
            PastPriceLine(item: .instrument(need.instrument), kind: .fetched, title: name(need.instrument),
                          source: need.details.flatMap(InstrumentText.sourceText(of:)), dates: need.dates)
        }
        lines += needs.rates.map { need in
            PastPriceLine(item: .fx(base: needs.baseCurrency, quote: need.quote), kind: .rate, title: need.quote.rawValue,
                          source: "ECB", dates: need.dates)
        }
        lines += needs.indices.map { need in
            PastPriceLine(item: .index(need.index), kind: .index, title: PastPriceText.title(of: need.index),
                          source: "Eurostat", dates: need.months.map(\.lastDay))
        }
        lines += needs.manualInstruments.sorted(by: byName).map { need in
            PastPriceLine(item: .instrument(need.instrument), kind: .manual, title: name(need.instrument),
                          source: "Typed in by hand", dates: need.dates)
        }
        lines += needs.unknownInstruments.map { need in
            PastPriceLine(item: .instrument(need.instrument), kind: .unknown, title: need.instrument.rawValue,
                          source: "Not in the library", dates: need.dates)
        }
        self.lines = lines
    }

    /// What's fetched: instruments with a price source, rates and indices.
    var fetchedLines: [PastPriceLine] { lines.filter { $0.kind != .manual && $0.kind != .unknown } }
    /// What's typed in: instruments without a price source, and unknown ones.
    var manualLines: [PastPriceLine] { lines.filter { $0.kind == .manual || $0.kind == .unknown } }

    var isEmpty: Bool { lines.isEmpty }
    /// Whether there's anything to fetch.
    var canFetch: Bool { needs.hasFetchable }

    /// "12 prices, 3 exchange rates and 1 inflation month to fetch.", with
    /// "3 prices to type in." after it when some have no price source.
    var summary: String {
        var parts: [String] = []
        if needs.priceCount > 0 { parts.append(PastPriceText.count(needs.priceCount, "price")) }
        if needs.rateCount > 0 { parts.append(PastPriceText.count(needs.rateCount, "exchange rate")) }
        if needs.indexMonthCount > 0 { parts.append(PastPriceText.count(needs.indexMonthCount, "inflation month")) }
        var sentences: [String] = []
        if !parts.isEmpty { sentences.append(OverviewAttention.list(parts) + " to fetch.") }
        if needs.manualPriceCount > 0 {
            sentences.append(PastPriceText.count(needs.manualPriceCount, "price") + " to type in.")
        }
        return sentences.isEmpty ? "Nothing is missing." : sentences.joined(separator: " ")
    }

    /// The Import Done step's lines: "12 past values have no price for
    /// XAU", for the instruments in `among` (all when `nil`) missing prices.
    func offers(among instruments: Set<InstrumentID>?, library: Library) -> [String] {
        lines.compactMap { line in
            guard let id = line.instrument, instruments.map({ $0.contains(id) }) ?? true else { return nil }
            let count = line.dates.count
            let values = count == 1 ? "1 past value has" : "\(count) past values have"
            return "\(values) no price for \(PastPriceText.shortName(of: id, in: library))"
        }
    }
}

/// How *Fill In Past Prices* words things.
enum PastPriceText {
    /// "1 price", "12 prices".
    static func count(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    /// "Inflation (Italy)" for `hicp-it`.
    static func title(of index: IndexID) -> String {
        index == .hicpIT ? "Inflation (Italy)" : index.rawValue
    }

    /// An instrument as the Import Done step names it: its ticker, the
    /// symbol it's fetched by, or its name (`XAU`).
    static func shortName(of id: InstrumentID, in library: Library) -> String {
        guard let instrument = library.instruments[id] else { return id.rawValue }
        if let ticker = instrument.ticker, !ticker.isEmpty { return ticker }
        if let symbol = instrument.priceSource?.symbol, !symbol.isEmpty { return symbol }
        return instrument.name
    }

    /// "Oct 2025", as a month and year.
    static func month(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.month(.abbreviated).year().locale(locale))
    }

    /// "Oct 2025 – Sep 2026", or "30 Sep 2026" for one date.
    static func range(_ first: CalendarDate, _ last: CalendarDate, locale: Locale = .current) -> String {
        if first == last { return AmountFormat.mediumDate(first, locale: locale) }
        if first.yearMonth == last.yearMonth {
            return AmountFormat.shortDate(first, locale: locale) + " – " + AmountFormat.mediumDate(last, locale: locale)
        }
        return month(first, locale: locale) + " – " + month(last, locale: locale)
    }

    /// "Oct 2025 – Sep 2026 · 12 dates", or "30 Sep 2026".
    static func dates(_ dates: [CalendarDate], locale: Locale = .current) -> String {
        guard let first = dates.first, let last = dates.last else { return "" }
        let range = range(first, last, locale: locale)
        return dates.count == 1 ? range : range + " · \(count(dates.count, "date"))"
    }

    /// Where the values came from: "Yahoo Finance · GC=F (history)"; for
    /// two sources, the newer first: "CoinGecko · ethereum back to Oct 2025,
    /// Yahoo Finance · ETH-EUR (history) before"; for more, each with its dates.
    static func sources(_ runs: [PastPriceSource], locale: Locale = .current) -> String? {
        switch runs.count {
        case 0:
            return nil
        case 1:
            return runs[0].origin.description
        case 2 where runs[0].origin != runs[1].origin:
            let (older, newer) = (runs[0], runs[1])
            return "\(newer.origin) back to \(month(newer.first, locale: locale)), \(older.origin) before"
        default:
            return runs.reversed().map { "\($0.origin) \(range($0.first, $0.last, locale: locale))" }
                .joined(separator: ", ")
        }
    }

    /// After a fill: "12 of 12", "8 of 12", "None"; before: the count.
    static func status(of line: PastPriceLine) -> String {
        guard let result = line.result else { return "\(line.dates.count)" }
        switch result.status {
        case .manual, .unknownInstrument: return "\(result.missing.count) to type in"
        case .notFilled: return "None"
        case .filled, .partlyFilled: return "\(result.filled.count) of \(result.needed.count)"
        }
    }
}

/// Runs *Fill In Past Prices* for its sheet: works out what's missing,
/// fetches it through the ``PriceStore`` with progress, and saves what's new
/// in one ``LibraryStore`` edit. A failure affects only its own line.
@Observable @MainActor
final class PastPriceFiller {
    enum Phase: Hashable, Sendable {
        /// Showing what's missing.
        case ready
        /// Fetching; how far it's got.
        case fetching(PastPriceProgress)
        case saving
        /// Fetched and saved; the lines have their results.
        case done
        /// Couldn't save (or fetch at all); the reason as sentences.
        case failed(String)
    }

    /// What's missing, with each line's result once the fill has run.
    private(set) var plan: PastPricePlan?
    private(set) var phase: Phase = .ready
    /// What the fill fetched.
    private(set) var fill: PastPriceFill?
    /// What saving added, and kept.
    private(set) var inserted: PastPriceInsertion?

    init() {}

    var isRunning: Bool {
        switch phase {
        case .fetching, .saving: true
        default: false
        }
    }

    /// Works out what's missing now, unless a fill is running or done.
    func prepare(library: LibraryStore, prices: PriceStore) {
        guard !isRunning, phase != .done else { return }
        plan = PastPricePlan(needs: prices.pastPriceNeeds(for: library.library), library: library.library)
        phase = .ready
    }

    /// Forgets the last fill's results and works out again what's missing,
    /// e.g. after giving an instrument a price source (*Check Again*).
    func reset(library: LibraryStore, prices: PriceStore) {
        guard !isRunning else { return }
        phase = .ready
        fill = nil
        inserted = nil
        prepare(library: library, prices: prices)
    }

    /// Whether *Fill In* can run: something to fetch, the library can be
    /// edited, prices can be fetched (not in previews), nothing running.
    func canRun(library: LibraryStore, prices: PriceStore) -> Bool {
        library.canEdit && prices.canFetch && !isRunning && phase != .done && plan?.canFetch == true
    }

    /// Fetches everything the plan lists, then saves it.
    func run(library: LibraryStore, prices: PriceStore) async {
        guard canRun(library: library, prices: prices), var plan else { return }
        phase = .fetching(PastPriceProgress(done: 0, total: plan.fetchedLines.count))
        let fetched = await prices.fillPastPrices(plan.needs, in: library.library) { [weak self] progress in
            self?.phase = .fetching(progress)
        }
        guard let fetched else {
            phase = .failed("Prices can't be fetched here.")
            return
        }
        fill = fetched
        plan.lines = Self.merge(plan.lines, with: fetched)
        self.plan = plan
        phase = .saving
        do {
            inserted = fetched.recordCount > 0 ? try await library.insertMissing(fetched) : PastPriceInsertion()
            phase = .done
        } catch {
            phase = .failed("The prices couldn't be saved. " + LibraryStore.describe(error))
        }
    }

    /// The lines with their results, plus a line for each rate the fill
    /// fetched only to convert prices.
    static func merge(_ lines: [PastPriceLine], with fill: PastPriceFill) -> [PastPriceLine] {
        var merged = lines.map { line in
            var line = line
            line.result = fill.result(for: line.item)
            return line
        }
        for result in fill.results where !merged.contains(where: { $0.item == result.item }) {
            guard case .fx(_, let quote) = result.item else { continue }
            let line = PastPriceLine(item: result.item, kind: .rate, title: quote.rawValue, source: "ECB",
                                     dates: result.needed, result: result)
            let index = merged.firstIndex { $0.kind == .index || $0.kind == .manual || $0.kind == .unknown }
                ?? merged.endIndex
            merged.insert(line, at: index)
        }
        return merged
    }

    /// "Fetching gold… 2 of 5", "Saving…", or what was added: "Added 12
    /// prices and 3 exchange rates." / "Nothing new to add."
    var statusText: String? {
        switch phase {
        case .ready:
            return plan?.summary
        case .fetching(let progress):
            let step = progress.total > 1 ? " \(progress.done) of \(progress.total)" : ""
            return "Fetching past prices…" + step
        case .saving:
            return "Saving…"
        case .done:
            guard let inserted else { return nil }
            var parts: [String] = []
            if inserted.prices > 0 { parts.append(PastPriceText.count(inserted.prices, "price")) }
            if inserted.fx > 0 { parts.append(PastPriceText.count(inserted.fx, "exchange rate")) }
            if inserted.indices > 0 { parts.append(PastPriceText.count(inserted.indices, "inflation month")) }
            var text = parts.isEmpty ? "Nothing new to add." : "Added " + OverviewAttention.list(parts) + "."
            if inserted.kept > 0 {
                text += " Kept \(PastPriceText.count(inserted.kept, "value")) the library had by then."
            }
            return text
        case .failed(let reason):
            return reason
        }
    }

    /// How many dates are still without a value, after a fill.
    var stillMissing: Int {
        (plan?.lines ?? []).reduce(0) { $0 + $1.missing.count }
    }
}

/// The note under a chart some of whose values couldn't be worked out
/// because a price or an exchange rate is missing (UI.md, "Account detail"
/// and "Overview"), with *Fill In Past Prices…*.
enum MissingValueNote {
    /// Under an account's chart, in its own currency: "Some values can't be
    /// shown: exchange rates for US$ are missing for Jun 2018 – Dec 2021."
    /// Then, for an account in another currency than the base one whose
    /// own values are there but can't be converted: "Net worth leaves out
    /// this account's values for Jun 2018 – Dec 2021: exchange rates for
    /// US$ are missing." `nil` when nothing is missing.
    static func account(chart: MissingValues?, netWorth: MissingValues?, name: (InstrumentID) -> String,
                        locale: Locale = .current) -> String? {
        var sentences: [String] = []
        if let chart = chart?.filter({ $0.item.isPriceOrRate }) {
            sentences.append("Some values can't be shown: "
                + OverviewAttention.list(clauses(chart, name: name, locale: locale)) + ".")
        }
        if let netWorth {
            let subjects = netWorth.gaps.map { subject($0.item, name: name, locale: locale) }
            sentences.append("Net worth leaves out this account's values \(when(netWorth.dates, locale: locale)): "
                + OverviewAttention.list(subjects) + " are missing.")
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// Under the Overview's chart: "Where the line is dashed, the total is
    /// partial: exchange rates for US$ are missing for Jun 2018 – Dec 2021
    /// (Brokerage), and 3 accounts have no value yet for Mar 2024 – Sep
    /// 2025 (Home, Mutuo casa and Old bank)."
    static func overview(_ missing: MissingValues, accountName: (AccountID) -> String,
                         instrumentName: (InstrumentID) -> String, locale: Locale = .current) -> String {
        var parts = missing.gaps.filter(\.item.isPriceOrRate).map { gap in
            clause(gap, name: instrumentName, locale: locale)
                + " (\(OverviewAttention.list(gap.accounts.map(accountName))))"
        }
        let unvalued = missing.gaps.filter { !$0.item.isPriceOrRate }
        let names = unvalued.flatMap(\.accounts).map(accountName)
        if let first = names.first {
            let dates = Set(unvalued.flatMap(\.dates)).sorted()
            parts.append(names.count == 1
                ? "\(first) has no value yet \(when(dates, locale: locale))"
                : "\(names.count) accounts have no value yet \(when(dates, locale: locale)) (\(shortList(names)))")
        }
        return "Where the line is dashed, the total is partial: " + OverviewAttention.list(parts) + "."
    }

    /// "A, B and C", or "A, B, C and 4 more".
    static func shortList(_ names: [String], limit: Int = 3) -> String {
        guard names.count > limit + 1 else { return OverviewAttention.list(names) }
        return names.prefix(limit).joined(separator: ", ") + " and \(names.count - limit) more"
    }

    /// "exchange rates for US$ are missing for Jun 2018 – Dec 2021", one per
    /// missing price or rate.
    static func clauses(_ missing: MissingValues, name: (InstrumentID) -> String,
                        locale: Locale = .current) -> [String] {
        missing.gaps.map { clause($0, name: name, locale: locale) }
    }

    static func clause(_ gap: MissingValues.Gap, name: (InstrumentID) -> String, locale: Locale = .current) -> String {
        "\(subject(gap.item, name: name, locale: locale)) are missing \(when(gap.dates, locale: locale))"
    }

    /// "exchange rates for US$", "prices for Gold coins".
    static func subject(_ item: MissingValues.Item, name: (InstrumentID) -> String,
                        locale: Locale = .current) -> String {
        switch item {
        case .rate(let from, _): "exchange rates for \(AmountFormat.symbol(for: from, locale: locale))"
        case .price(let instrument): "prices for \(name(instrument))"
        case .noValuation(let account): "values of \(account.rawValue)"
        }
    }

    /// "for Jun 2018 – Dec 2021", or "on 30 Sep 2026" for one date.
    static func when(_ dates: [CalendarDate], locale: Locale = .current) -> String {
        guard let first = dates.first, let last = dates.last else { return "" }
        return first == last
            ? "on \(AmountFormat.mediumDate(first, locale: locale))"
            : "for \(PastPriceText.range(first, last, locale: locale))"
    }
}

/// The note under a chart whose values use old prices (UI.md, "Overview" and
/// "Account detail").
enum OldPriceNote {
    /// "10 values in the chart use a price more than 31 days older than
    /// their date (Gold coins)."
    static func text(_ summary: OldPriceSummary, name: (InstrumentID) -> String) -> String {
        let count = summary.dates.count
        let values = count == 1 ? "1 value in the chart uses" : "\(count) values in the chart use"
        let names = OverviewAttention.list(summary.instruments.map(name))
        return "\(values) a price more than \(Valuator.oldPriceDays) days older than "
            + (count == 1 ? "its" : "their") + " date (\(names))."
    }
}
