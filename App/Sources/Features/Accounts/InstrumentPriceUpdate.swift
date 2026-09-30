import Foundation
import Model
import Observation
import Prices

// Updating prices outside a check-in (UI.md, "Instruments"): *Update Prices*
// fetches today's price of every instrument an open account holds that has a
// price source, with the exchange rates that value them in the base
// currency, and saves them in one edit. A price or rate typed in by hand for
// the same date is kept, as in the check-in, unless you choose Update on its
// row. Free of SwiftUI so it can be checked on Linux.

/// What *Update Prices* fetches on a date.
struct InstrumentPriceUpdatePlan: Hashable, Sendable {
    var date: CalendarDate
    var baseCurrency: CurrencyCode
    /// The instruments to fetch, sorted by name, then ID.
    var instruments: [Instrument]
    /// Their currencies other than the base currency, whose rates are fetched too, sorted.
    var currencies: [CurrencyCode]
    /// Instruments without a price source: their prices are typed in. Sorted.
    var typedInstruments: [InstrumentID]
    /// Instruments with a price source that no account open on the date
    /// holds (sold, closed or not used yet). Sorted.
    var unheldInstruments: [InstrumentID]

    init(date: CalendarDate, baseCurrency: CurrencyCode, instruments: [Instrument],
         typedInstruments: [InstrumentID] = [], unheldInstruments: [InstrumentID] = []) {
        self.date = date
        self.baseCurrency = baseCurrency
        self.instruments = instruments.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
        currencies = Set(instruments.map(\.currency)).subtracting([baseCurrency]).sorted()
        self.typedInstruments = typedInstruments.sorted()
        self.unheldInstruments = unheldInstruments.sorted()
    }

    /// Every instrument with a price source that's held (quantity not zero)
    /// in the latest valuation of an account open on `date`: the ones a
    /// check-in on that date fetches.
    init(library: Library, on date: CalendarDate) {
        let needs = CheckInPriceNeeds(library: library, date: date, indices: [])
        let held = Set(needs.instruments.map(\.id))
        let all = library.instruments.values
        self.init(date: date, baseCurrency: library.settings.baseCurrency, instruments: needs.instruments,
                  typedInstruments: all.filter { !Self.isFetched($0) }.map(\.id),
                  unheldInstruments: all.filter { Self.isFetched($0) && !held.contains($0.id) }.map(\.id))
    }

    /// Just `ids`, held or not (a row's *Update Price*); instruments without
    /// a price source are left out.
    init(instruments ids: [InstrumentID], library: Library, on date: CalendarDate) {
        let found = ids.compactMap { library.instruments[$0] }
        self.init(date: date, baseCurrency: library.settings.baseCurrency,
                  instruments: found.filter(Self.isFetched),
                  typedInstruments: found.filter { !Self.isFetched($0) }.map(\.id))
    }

    /// Whether an instrument's prices are fetched: it has a price source
    /// with a symbol, and its provider isn't `manual` (as in the check-in).
    static func isFetched(_ instrument: Instrument) -> Bool {
        guard let source = instrument.priceSource else { return false }
        return source.provider.rawValue != "manual" && !source.symbol.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isEmpty: Bool { instruments.isEmpty }

    /// What to ask the price service for one instrument: its price, and the
    /// rate of its currency when that isn't the base currency.
    func needs(for instrument: Instrument) -> CheckInPriceNeeds {
        CheckInPriceNeeds(date: date, baseCurrency: baseCurrency, instruments: [instrument],
                          currencies: instrument.currency == baseCurrency ? [] : [instrument.currency])
    }
}

/// One *Update Prices* run: a line per instrument and per exchange rate,
/// filled in as the fetches arrive, then settled against the library as it
/// is when they're done, which says what to save.
struct InstrumentPriceUpdate: Hashable, Sendable {
    /// Where a line stands.
    enum Status: Hashable, Sendable {
        /// Being fetched.
        case fetching
        /// Fetched, not saved yet.
        case fetched
        /// Saved: a new price, or a different one from the latest saved.
        case updated
        /// The same as the latest saved price (saved again for the date if
        /// that one is older).
        case unchanged
        /// A value typed in by hand for the date was kept; see ``Line/typed``.
        case keptTyped
        /// Not fetched, or not saved; the reason reads as a sentence.
        case failed(String)
    }

    /// An instrument's price or an exchange rate.
    struct Line: Identifiable, Hashable, Sendable {
        var item: PriceListEntry.Item
        /// The instrument's name, or the currency code for a rate.
        var title: String
        var status: Status
        /// The fetched price (instrument lines).
        var price: PriceRecord?
        /// The fetched rate (rate lines).
        var rate: FXRecord?
        /// The latest value saved before this update, and its date.
        var previous: Decimal?
        var previousDate: CalendarDate?
        /// The value typed in by hand for the date, when it was kept.
        var typed: Decimal?
        /// "Yahoo Finance · VWCE.DE".
        var source: String?
        /// The provider's ID for the symbol when it differs from the one
        /// typed ("ethereum" for "ETH").
        var resolvedSymbol: String?
        /// The day the fetched value is from, e.g. Friday's close on a Sunday.
        var observedOn: CalendarDate?

        var id: PriceListEntry.Item { item }

        /// The fetched value: a price or a rate.
        var value: Decimal? { price?.price ?? rate?.rate }

        var isInstrument: Bool {
            if case .instrument = item { true } else { false }
        }

        var instrument: InstrumentID? {
            if case .instrument(let id) = item { id } else { nil }
        }

        /// Why it failed, if it did.
        var failure: String? {
            if case .failed(let reason) = status { reason } else { nil }
        }

        /// Whether it's still being fetched or saved.
        var isPending: Bool { status == .fetching || status == .fetched }
    }

    /// What a settled run saves.
    struct Records: Hashable, Sendable {
        var prices: [PriceRecord] = []
        var fxRates: [FXRecord] = []

        var isEmpty: Bool { prices.isEmpty && fxRates.isEmpty }
    }

    var date: CalendarDate
    var baseCurrency: CurrencyCode
    /// Instruments, sorted by name.
    private(set) var instruments: [Line]
    /// Exchange rates against the base currency, sorted by currency.
    private(set) var rates: [Line]
    /// How many instruments weren't fetched because they're typed in, or no
    /// open account holds them.
    var typedCount: Int
    var unheldCount: Int
    /// When the run finished, `nil` while it's going.
    var finishedAt: Date?

    /// A run about to fetch `plan`, with every line waiting.
    init(plan: InstrumentPriceUpdatePlan) {
        date = plan.date
        baseCurrency = plan.baseCurrency
        instruments = []
        rates = []
        typedCount = plan.typedInstruments.count
        unheldCount = plan.unheldInstruments.count
        add(plan)
    }

    var lines: [Line] { instruments + rates }

    /// The line of an instrument or rate.
    func line(for item: PriceListEntry.Item) -> Line? {
        lines.first { $0.item == item }
    }

    /// Adds the lines of `plan` (e.g. one more instrument), or sets them
    /// fetching again.
    mutating func add(_ plan: InstrumentPriceUpdatePlan) {
        finishedAt = nil
        for instrument in plan.instruments {
            let line = Line(item: .instrument(instrument.id), title: instrument.name, status: .fetching,
                            source: InstrumentText.sourceText(of: instrument))
            if let index = instruments.firstIndex(where: { $0.item == line.item }) {
                instruments[index] = line
            } else {
                instruments.append(line)
            }
        }
        instruments.sort { ($0.title.lowercased(), $0.item) < ($1.title.lowercased(), $1.item) }
        for currency in plan.currencies where line(for: .fx(base: baseCurrency, quote: currency)) == nil {
            rates.append(Line(item: .fx(base: baseCurrency, quote: currency), title: currency.rawValue,
                              status: .fetching))
        }
        rates.sort { $0.item < $1.item }
    }

    // MARK: Fetching

    /// Takes in what one fetch returned: each instrument's price or why it
    /// failed, and the rates, including those used only to convert a quote.
    mutating func receive(_ fetched: CheckInPrices) {
        for entry in fetched.entries {
            switch entry.item {
            case .instrument(let id):
                guard let index = instruments.firstIndex(where: { $0.item == entry.item }) else { continue }
                var line = instruments[index]
                line.source = InstrumentText.sourceText(source: entry.source, symbol: entry.symbol) ?? line.source
                line.resolvedSymbol = entry.shownResolvedSymbol
                switch entry.outcome {
                case .fetched(let details):
                    if let price = fetched.prices.first(where: { $0.instrument == id }) {
                        line.status = .fetched
                        line.price = price
                        line.observedOn = details.observedOn
                    } else {
                        line.status = .failed("No price came back.")
                    }
                case .failed(let error):
                    line.status = .failed(error.description)
                case .manual:
                    line.status = .failed("It has no price source: type its price in.")
                }
                instruments[index] = line
            case .fx(let base, let quote):
                guard let index = rates.firstIndex(where: { $0.item == entry.item }) else { continue }
                rates[index].source = InstrumentText.sourceText(source: entry.source, symbol: entry.symbol)
                if let failure = entry.failure, rates[index].status == .fetching,
                   !fetched.fx.contains(where: { ($0.base, $0.quote) == (base, quote) }) {
                    rates[index].status = .failed(failure.description)
                }
            case .index:
                continue
            }
        }
        for rate in fetched.fx where rate.base == baseCurrency {
            let item = PriceListEntry.Item.fx(base: rate.base, quote: rate.quote)
            if let index = rates.firstIndex(where: { $0.item == item }) {
                rates[index].status = .fetched
                rates[index].rate = rate
            } else {
                rates.append(Line(item: item, title: rate.quote.rawValue, status: .fetched, rate: rate,
                                  source: InstrumentText.sourceText(source: rate.source, symbol: nil)))
                rates.sort { $0.item < $1.item }
            }
        }
    }

    /// Marks the lines still waiting for an answer, once the fetches are
    /// over, as failed.
    mutating func failUnanswered() {
        let failure = Status.failed("No answer came back. Try again.")
        for index in instruments.indices where instruments[index].status == .fetching {
            instruments[index].status = failure
        }
        for index in rates.indices where rates[index].status == .fetching {
            rates[index].status = failure
        }
    }

    /// Marks an instrument whose fetched price was kept because of a typed
    /// one as fetched again, so the next ``settle(in:replacingTyped:)`` can
    /// save it. Returns whether there was such a price.
    mutating func reconsider(_ id: InstrumentID) -> Bool {
        guard let index = instruments.firstIndex(where: { $0.item == .instrument(id) }),
              instruments[index].status == .keptTyped, instruments[index].price != nil
        else { return false }
        instruments[index].status = .fetched
        finishedAt = nil
        return true
    }

    // MARK: Saving

    /// Decides what to save against `library` as it is now, and returns it.
    /// Fetched lines become updated, unchanged or kept:
    ///
    /// - A value typed in by hand for the same date is kept (the fetched one
    ///   isn't saved), unless its instrument is in `replacingTyped`.
    /// - A value equal to the latest saved one is unchanged; it's saved for
    ///   the date only when the latest is older.
    /// - Anything else is saved, replacing a fetched value for the date.
    mutating func settle(in library: Library, replacingTyped: Set<InstrumentID> = []) -> Records {
        var records = Records()
        for index in instruments.indices where instruments[index].status == .fetched {
            guard let price = instruments[index].price else { continue }
            let history = library.prices(for: price.instrument)
            let sameDay = history.last { $0.date == price.date }
            let latest = sameDay ?? history.last { $0.date < price.date }
            let outcome = Self.outcome(fetched: Compared(price), sameDay: sameDay.map { Compared($0) },
                                       latest: latest.map { Compared($0) },
                                       replacingTyped: replacingTyped.contains(price.instrument))
            instruments[index].status = outcome.status
            instruments[index].previous = latest?.price
            instruments[index].previousDate = latest?.date
            instruments[index].typed = outcome.status == .keptTyped ? sameDay?.price : nil
            if outcome.writes { records.prices.append(price) }
        }
        for index in rates.indices where rates[index].status == .fetched {
            guard let rate = rates[index].rate else { continue }
            let history = library.fxRates(base: rate.base, quote: rate.quote)
            let sameDay = history.last { $0.date == rate.date }
            let latest = sameDay ?? history.last { $0.date < rate.date }
            let outcome = Self.outcome(fetched: Compared(rate), sameDay: sameDay.map { Compared($0) },
                                       latest: latest.map { Compared($0) }, replacingTyped: false)
            rates[index].status = outcome.status
            rates[index].previous = latest?.rate
            rates[index].previousDate = latest?.date
            rates[index].typed = outcome.status == .keptTyped ? sameDay?.rate : nil
            if outcome.writes { records.fxRates.append(rate) }
        }
        records.prices = records.prices.sortedByKey()
        records.fxRates = records.fxRates.sortedByKey()
        return records
    }

    /// A price (with its currency) or a rate, as ``settle(in:replacingTyped:)`` compares them.
    private struct Compared {
        var value: Decimal
        var currency: CurrencyCode?
        var source: DataSource?

        init(_ price: PriceRecord) {
            value = price.price
            currency = price.currency
            source = price.source
        }

        init(_ rate: FXRecord) {
            value = rate.rate
            source = rate.source
        }

        func sameValue(as other: Compared) -> Bool {
            value == other.value && currency == other.currency
        }
    }

    private static func outcome(fetched: Compared, sameDay: Compared?, latest: Compared?,
                                replacingTyped: Bool) -> (status: Status, writes: Bool) {
        let equalsLatest = latest?.sameValue(as: fetched) ?? false
        if let sameDay, sameDay.source == .manual, !replacingTyped {
            return (equalsLatest ? .unchanged : .keptTyped, false)
        }
        if equalsLatest {
            // Already saved for the date: nothing to write. Saved earlier:
            // saved again, so the price counts as today's.
            return (.unchanged, sameDay == nil)
        }
        return (.updated, true)
    }

    /// Marks the lines whose records couldn't be saved as failed.
    mutating func saveFailed(_ records: Records, reason: String) {
        let failure = Status.failed("Couldn't save it. \(reason)")
        let prices = Set(records.prices.map(\.instrument))
        for index in instruments.indices where instruments[index].instrument.map(prices.contains) == true {
            instruments[index].status = failure
        }
        let rates = Set(records.fxRates.map(\.quote))
        for index in self.rates.indices {
            if case .fx(_, let quote) = self.rates[index].item, rates.contains(quote) {
                self.rates[index].status = failure
            }
        }
    }

    // MARK: Progress

    /// Whether any line is still being fetched or saved.
    var isFinished: Bool { !lines.contains(where: \.isPending) }

    /// Instruments done (fetched or failed), and how many there are.
    var progress: (done: Int, total: Int) {
        (instruments.count { $0.status != .fetching }, instruments.count)
    }

    /// Lines by status: how many instruments were updated, unchanged, kept or failed.
    var counts: (updated: Int, unchanged: Int, kept: Int, failed: Int) {
        (instruments.count { $0.status == .updated }, instruments.count { $0.status == .unchanged },
         instruments.count { $0.status == .keptTyped }, instruments.count { $0.failure != nil })
    }

    /// Whether anything wants a look: a failure, or a typed value kept.
    var needsAttention: Bool {
        lines.contains { $0.failure != nil || $0.status == .keptTyped }
    }

    /// "Updating prices… 2 of 5", "3 updated · 1 unchanged · 1 failed", or
    /// "No prices to update".
    var summary: String {
        if !isFinished {
            let (done, total) = progress
            return total > 1 ? "Updating prices… \(done) of \(total)" : "Updating prices…"
        }
        guard !instruments.isEmpty else { return "No prices to update" }
        let counts = counts
        var parts: [String] = []
        if counts.updated > 0 { parts.append("\(counts.updated) updated") }
        if counts.unchanged > 0 { parts.append("\(counts.unchanged) unchanged") }
        if counts.kept > 0 { parts.append("\(counts.kept) typed kept") }
        if counts.failed > 0 { parts.append("\(counts.failed) failed") }
        let failedRates = rates.count { $0.failure != nil }
        if failedRates > 0 { parts.append(failedRates == 1 ? "1 rate failed" : "\(failedRates) rates failed") }
        return parts.joined(separator: " · ")
    }

    /// Why instruments weren't fetched: "Not fetched: 1 typed in by hand,
    /// 2 not held in an open account."; `nil` when every one was.
    var skippedText: String? {
        var parts: [String] = []
        if typedCount > 0 { parts.append("\(typedCount) typed in by hand") }
        if unheldCount > 0 { parts.append("\(unheldCount) not held in an open account") }
        return parts.isEmpty ? nil : "Not fetched: " + parts.joined(separator: ", ") + "."
    }
}

extension InstrumentPriceUpdate.Line {
    /// Where the value comes from: "Yahoo Finance · VWCE.DE", or
    /// "CoinGecko · ETH → ethereum" when the provider knows the symbol by
    /// another ID.
    var sourceLine: String? {
        guard let resolvedSymbol, let source else { return source }
        return "\(source) → \(resolvedSymbol)"
    }

    /// The fetched value: "140 EUR" for a price, "1,15" for a rate.
    func valueText(locale: Locale = .current) -> String? {
        if let price { return InstrumentText.price(price.price, currency: price.currency, locale: locale) }
        return rate.map { AmountFormat.number($0.rate, maxDigits: 4, locale: locale) }
    }

    /// What happened, as a sentence: "Was 137,10 EUR on 29 Sep.",
    /// "Unchanged since 30 Sep.", why it failed, or that a typed value was kept.
    func detail(locale: Locale = .current) -> String {
        let currency = price?.currency
        func amount(_ value: Decimal) -> String { InstrumentText.price(value, currency: currency, locale: locale) }
        var text: String
        switch status {
        case .fetching:
            return "Fetching…"
        case .fetched:
            return "Saving…"
        case .updated:
            if let previous, let previousDate {
                text = "Was \(amount(previous)) on \(AmountFormat.shortDate(previousDate, locale: locale))."
            } else {
                text = isInstrument ? "Its first price." : "The first rate."
            }
        case .unchanged:
            text = previousDate.map { "Unchanged since \(AmountFormat.shortDate($0, locale: locale))." } ?? "Unchanged."
        case .keptTyped:
            let typed = typed.map(amount) ?? "a value"
            let date = (price?.date ?? rate?.date).map { AmountFormat.shortDate($0, locale: locale) } ?? "this date"
            return isInstrument
                ? "You typed in \(typed) for \(date), so it's kept. Update replaces it with the fetched price."
                : "You typed in \(typed) for \(date), so it's kept."
        case .failed(let reason):
            return reason
        }
        if let observedOn, let date = price?.date, observedOn < date {
            text += " Price as of \(AmountFormat.shortDate(observedOn, locale: locale))."
        }
        return text
    }
}

/// Runs *Update Prices* for the Instruments screen: fetches through the
/// ``PriceStore`` one instrument at a time (all at once), shows each result
/// as it arrives, and saves what's new in one ``LibraryStore`` edit when the
/// fetches are done. Failures affect only their own line.
@Observable @MainActor
final class InstrumentPriceUpdater {
    /// The current or latest run.
    private(set) var run: InstrumentPriceUpdate?
    private(set) var isRunning = false

    init() {}

    /// Whether prices can be updated: the library can be edited, prices can
    /// be fetched (not in previews), and no update is running.
    func canUpdate(library: LibraryStore, prices: PriceStore) -> Bool {
        library.canEdit && prices.canFetch && !isRunning
    }

    /// Fetches today's price of every held instrument with a price source
    /// (``InstrumentPriceUpdatePlan/init(library:on:)``) and the rates
    /// that value them, fresh rather than from the session's cache, and
    /// saves them.
    func updateAll(library: LibraryStore, prices: PriceStore, on date: CalendarDate = .today()) async {
        guard canUpdate(library: library, prices: prices) else { return }
        let plan = InstrumentPriceUpdatePlan(library: library.library, on: date)
        run = InstrumentPriceUpdate(plan: plan)
        await fetchAndSave(plan, library: library, prices: prices, replacingTyped: [])
    }

    /// Updates one instrument, held or not: a row's *Update Price*, or
    /// *Try Again*. With `replacingTyped`, its fetched price replaces one
    /// typed in by hand for the date; a price already fetched in this run
    /// is saved without fetching again.
    func update(_ id: InstrumentID, replacingTyped: Bool = false, library: LibraryStore, prices: PriceStore,
                on date: CalendarDate = .today()) async {
        guard canUpdate(library: library, prices: prices) else { return }
        let replacing: Set<InstrumentID> = replacingTyped ? [id] : []
        if replacingTyped, var run, run.date == date, run.reconsider(id) {
            self.run = run
            save(library: library, replacingTyped: replacing)
            return
        }
        let plan = InstrumentPriceUpdatePlan(instruments: [id], library: library.library, on: date)
        guard !plan.isEmpty else { return }
        if var run, run.date == date {
            run.add(plan)
            self.run = run
        } else {
            run = InstrumentPriceUpdate(plan: plan)
        }
        await fetchAndSave(plan, library: library, prices: prices, replacingTyped: replacing)
    }

    /// Clears the results, unless an update is running.
    func dismiss() {
        guard !isRunning else { return }
        run = nil
    }

    private func fetchAndSave(_ plan: InstrumentPriceUpdatePlan, library: LibraryStore, prices: PriceStore,
                              replacingTyped: Set<InstrumentID>) async {
        isRunning = true
        defer { isRunning = false }
        await prices.fetchEach(plan.instruments.map(plan.needs(for:)), refresh: true) { fetched in
            run?.receive(fetched)
        }
        save(library: library, replacingTyped: replacingTyped)
    }

    /// Settles the run against the library as it is now and saves the new
    /// records in one edit.
    private func save(library: LibraryStore, replacingTyped: Set<InstrumentID>) {
        guard var run else { return }
        run.failUnanswered()
        let records = run.settle(in: library.library, replacingTyped: replacingTyped)
        if !records.isEmpty {
            do {
                try library.upsert(prices: records.prices, fxRates: records.fxRates)
            } catch {
                run.saveFailed(records, reason: LibraryStore.describe(error))
            }
        }
        run.finishedAt = Date()
        self.run = run
    }
}

extension PriceListEntry {
    /// The provider's ID for the symbol when it differs from the one typed
    /// ("ETH" → "ethereum"), shown next to fetch results.
    ///
    /// Always `nil` on this branch: once the Prices module's CoinGecko ticker
    /// lookup (`PriceListEntry.resolvedSymbol`) is merged, return
    /// `resolvedSymbol` here.
    var shownResolvedSymbol: String? { nil }
}

extension Library {
    /// The price saved for `instrument` on exactly `date`, if any.
    func savedPrice(of instrument: InstrumentID, on date: CalendarDate) -> PriceRecord? {
        let key = PriceKey(instrument: instrument, date: date)
        return months[date.yearMonth]?.prices.first { $0.key == key }
    }

    /// The rate saved for `base`/`quote` on exactly `date`, if any.
    func savedRate(base: CurrencyCode, quote: CurrencyCode, on date: CalendarDate) -> FXRecord? {
        let key = FXKey(base: base, quote: quote, date: date)
        return months[date.yearMonth]?.fx.first { $0.key == key }
    }
}
