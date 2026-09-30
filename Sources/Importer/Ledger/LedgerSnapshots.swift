import Foundation
import Model

/// Market prices and exchange rates from the journal, to value postings:
/// `P` directives, and the prices and costs written on transactions.
struct LedgerPriceBook {
    private struct Pair: Hashable {
        var from: CurrencyCode
        var to: CurrencyCode
    }

    /// Per commodity: prices per unit, by date (on one date, `P` wins).
    private var prices: [String: [(date: CalendarDate, price: LedgerAmount)]] = [:]
    private var rates: [Pair: [(date: CalendarDate, rate: Decimal)]] = [:]
    private var currencies: [CurrencyCode] = []

    init(journal: LedgerJournal, currency: (String) -> CurrencyCode?) {
        var entries: [(date: CalendarDate, commodity: String, price: LedgerAmount)] = []
        for transaction in journal.transactions {
            for posting in transaction.postings where posting.amount.quantity != 0 {
                let unit = posting.unitPrice ?? posting.cost.map {
                    LedgerAmount($0.quantity / posting.amount.quantity, $0.commodity)
                }
                if let unit, unit.quantity > 0 {
                    entries.append((transaction.date, posting.amount.commodity, unit))
                }
            }
        }
        entries += journal.prices.map { ($0.date, $0.commodity, $0.price) }
        var ordered: [(offset: Int, element: (date: CalendarDate, commodity: String, price: LedgerAmount))] =
            Array(entries.enumerated())
        ordered.sort { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
        var seen = Set<CurrencyCode>()
        for (_, entry) in ordered {
            if let from = currency(entry.commodity), let to = currency(entry.price.commodity) {
                guard from != to else { continue }
                rates[Pair(from: from, to: to), default: []].append((entry.date, entry.price.quantity))
                for code in [from, to] where seen.insert(code).inserted { currencies.append(code) }
            } else {
                prices[entry.commodity, default: []].append((entry.date, entry.price))
            }
        }
    }

    /// The latest price of one unit of a commodity on or before `date`.
    func price(of commodity: String, on date: CalendarDate) -> LedgerAmount? {
        prices[commodity]?.last { $0.date <= date }?.price
    }

    /// `amount` converted at the latest rate on or before `date`: direct,
    /// inverse (the more recent of the two), or through another currency.
    func convert(_ amount: Decimal, from: CurrencyCode, to: CurrencyCode, on date: CalendarDate) -> Decimal? {
        if from == to || amount == 0 { return amount }
        if let rate = rate(from: from, to: to, on: date) { return amount * rate }
        for pivot in currencies where pivot != from && pivot != to {
            if let first = rate(from: from, to: pivot, on: date), let second = rate(from: pivot, to: to, on: date) {
                return amount * first * second
            }
        }
        return nil
    }

    private func rate(from: CurrencyCode, to: CurrencyCode, on date: CalendarDate) -> Decimal? {
        let direct = rates[Pair(from: from, to: to)]?.last { $0.date <= date }
        let inverse = rates[Pair(from: to, to: from)]?.last { $0.date <= date }
        switch (direct, inverse) {
        case (let direct?, let inverse?):
            return inverse.date > direct.date && inverse.rate != 0 ? 1 / inverse.rate : direct.rate
        case (let direct?, nil): return direct.rate
        case (nil, let inverse?): return inverse.rate != 0 ? 1 / inverse.rate : nil
        case (nil, nil): return nil
        }
    }
}

/// What a library account holds: cash per currency, and per instrument its
/// quantity and average cost.
private struct Holdings {
    var cash: [CurrencyCode: Decimal] = [:]
    var quantities: [InstrumentID: Decimal] = [:]
    /// Total cost per instrument in the account's currency; `nil` when unknown.
    var costs: [InstrumentID: Decimal?] = [:]

    mutating func apply(_ event: LedgerSnapshotBuilder.Event) {
        for (currency, change) in event.cash { cash[currency, default: 0] += change }
        for (instrument, change) in event.quantities {
            let before = quantities[instrument] ?? 0
            let after = before + change
            quantities[instrument] = after
            let cost = costs[instrument] ?? 0
            if after <= 0 {
                costs[instrument] = after == 0 ? 0 : nil
            } else if change > 0 {
                let added = event.addedCosts[instrument] ?? nil
                costs[instrument] = before <= 0 ? added : (cost.flatMap { old in added.map { old + $0 } })
            } else if change < 0 {
                costs[instrument] = cost.map { $0 * after / before }
            }
        }
    }

    var isZero: Bool {
        cash.values.allSatisfy { abs($0) < Decimal(string: "0.005")! }
            && quantities.values.allSatisfy { abs($0) < Decimal(string: "0.000000005")! }
    }
}

/// Turns a journal into valuations, prices and FX rates.
///
/// For each library account, at each snapshot date: its holdings (a
/// balance, or positions with their average cost plus cash), and its flow:
/// the money added or taken out since the previous snapshot. A posting's
/// counterparts decide the flow: moves within the account and returns
/// (dividends, interest, fees) aren't flows; other tracked accounts,
/// ignored ones, income, expenses and equity are.
struct LedgerSnapshotBuilder {
    /// One transaction's effect on one library account.
    struct Event {
        var date: CalendarDate
        var location: LedgerLocation
        var cash: [CurrencyCode: Decimal] = [:]
        var quantities: [InstrumentID: Decimal] = [:]
        /// The cost of quantities added, in the account's currency; `nil` when unknown.
        var addedCosts: [InstrumentID: Decimal?] = [:]
        /// `nil` when some value is unknown.
        var flow: Decimal?
    }

    let journal: LedgerJournal
    let mapper: LedgerMapper
    let library: Library
    let settings: LedgerImportSettings
    let until: CalendarDate?
    let book: LedgerPriceBook

    private(set) var records: [ImportedRecord] = []
    private(set) var notes: [LedgerDiagnostic] = []
    /// Accounts whose balance reaches zero and stays there, and when.
    private(set) var closings: [AccountID: CalendarDate] = [:]
    /// Each library account's first posting.
    private(set) var firstPostings: [AccountID: CalendarDate] = [:]
    private var events: [AccountID: [Event]] = [:]

    /// A balance that stays zero for this many days before the journal ends
    /// proposes closing the account (so a card paid off last week doesn't).
    static let closingDelay = 45

    init(journal: LedgerJournal, mapper: LedgerMapper, library: Library, settings: LedgerImportSettings,
         until: CalendarDate?) {
        self.journal = journal
        self.mapper = mapper
        self.library = library
        self.settings = settings
        self.until = until
        book = LedgerPriceBook(journal: journal, currency: mapper.currency(of:))
    }

    mutating func build() {
        collectEvents()
        for account in events.keys.sorted() { snapshots(of: account) }
        prices()
    }

    // MARK: - Accounts

    private func account(_ id: AccountID) -> Account? {
        library.accounts[id] ?? mapper.newAccounts[id]
    }

    private func currency(of id: AccountID) -> CurrencyCode {
        account(id)?.currency ?? library.settings.baseCurrency
    }

    // MARK: - Events

    private mutating func collectEvents() {
        for transaction in journal.transactions {
            var tracked: [(account: AccountID, postings: [LedgerPosting])] = []
            var flows: [LedgerPosting] = []
            var returns: [LedgerPosting] = []
            for posting in transaction.postings where posting.kind != .unbalancedVirtual {
                if mapper.role(of: posting.account).isNetWorth {
                    if let id = mapper.libraryAccount(of: posting.account) {
                        if let index = tracked.firstIndex(where: { $0.account == id }) {
                            tracked[index].postings.append(posting)
                        } else {
                            tracked.append((id, [posting]))
                        }
                    } else {
                        flows.append(posting)
                    }
                } else if mapper.isReturnsAccount(posting.account) {
                    returns.append(posting)
                } else {
                    flows.append(posting)
                }
            }
            guard !tracked.isEmpty else { continue }
            let date = transaction.date
            // With several tracked accounts, returns go to the first one they pay into (or out of).
            var returnsAccount = tracked[0].account
            if tracked.count > 1, !returns.isEmpty {
                for (id, postings) in tracked {
                    let currency = currency(of: id)
                    let own = sum(postings, in: currency, on: date)
                    let fromReturns = sum(returns, in: currency, on: date).map { -$0 }
                    if let own, let fromReturns, fromReturns != 0, (own > 0) == (fromReturns > 0) {
                        returnsAccount = id
                        break
                    }
                }
            }
            for (id, postings) in tracked {
                firstPostings[id] = firstPostings[id] ?? date
                let currency = currency(of: id)
                var event = Event(date: date, location: transaction.location)
                var added: [InstrumentID: (quantity: Decimal, cost: Decimal?)] = [:]
                for posting in postings {
                    switch mapper.commodities[posting.amount.commodity]?.mapping {
                    case .currency(let code)?:
                        event.cash[code, default: 0] += posting.amount.quantity
                    case .instrument(let instrument)?:
                        event.quantities[instrument, default: 0] += posting.amount.quantity
                        if posting.amount.quantity > 0 {
                            // What was paid; a quantity that came as a return (staking) costs its
                            // market value; anything else without a cost makes the cost unknown.
                            let cost: Decimal? = if let written = posting.cost {
                                mapper.currency(of: written.commodity).flatMap {
                                    book.convert(written.quantity, from: $0, to: currency, on: date)
                                }
                            } else if flows.isEmpty, !returns.isEmpty {
                                value(of: posting, in: currency, on: date)
                            } else {
                                nil
                            }
                            var entry = added[instrument] ?? (0, 0)
                            entry.quantity += posting.amount.quantity
                            entry.cost = entry.cost.flatMap { total in cost.map { total + $0 } }
                            added[instrument] = entry
                        }
                    case .ignored?, nil:
                        break
                    }
                }
                for (instrument, entry) in added where (event.quantities[instrument] ?? 0) > 0 && entry.quantity > 0 {
                    let net = event.quantities[instrument]!
                    event.addedCosts[instrument] = entry.cost.map { $0 * net / entry.quantity }
                }
                // The flow: with one tracked account, what the flow counterparts brought (moves
                // within the account and returns bring nothing); with several, each one's own
                // postings, less the returns for the account they went to.
                if tracked.count == 1 {
                    event.flow = sum(flows, in: currency, on: date).map { -$0 }
                } else if returns.isEmpty || id != returnsAccount {
                    event.flow = sum(postings, in: currency, on: date)
                } else {
                    event.flow = sum(postings, in: currency, on: date).flatMap { own in
                        sum(returns, in: currency, on: date).map { own + $0 }
                    }
                }
                if event.flow == nil {
                    let unvalued = (postings + flows + returns).first { value(of: $0, in: currency, on: date) == nil }
                    let what = unvalued.map { "\($0.amount) in \($0.account)" } ?? "a posting"
                    notes.append(LedgerDiagnostic(
                        .warning, "\(what) can't be valued in \(currency.rawValue) on \(date): there's no @ cost and "
                            + "no P price for it. The flow of \(account(id)?.name ?? id.rawValue) is left unknown.",
                        at: transaction.location))
                }
                events[id, default: []].append(event)
            }
        }
    }

    /// The postings' total value in `currency`; `nil` if one can't be valued.
    private func sum(_ postings: [LedgerPosting], in currency: CurrencyCode, on date: CalendarDate) -> Decimal? {
        var total: Decimal = 0
        for posting in postings {
            guard let value = value(of: posting, in: currency, on: date) else { return nil }
            total += value
        }
        return total
    }

    /// A posting's value in `currency`: a currency amount converted; a
    /// commodity at its cost, else at the latest price; `nil` if unknown.
    func value(of posting: LedgerPosting, in currency: CurrencyCode, on date: CalendarDate) -> Decimal? {
        let symbol = posting.amount.commodity
        if case .ignored? = mapper.commodities[symbol]?.mapping { return 0 }
        if let code = mapper.currency(of: symbol) {
            if code == currency { return posting.amount.quantity }
            if let cost = posting.cost, let costCurrency = mapper.currency(of: cost.commodity) {
                return book.convert(cost.quantity, from: costCurrency, to: currency, on: date)
            }
            return book.convert(posting.amount.quantity, from: code, to: currency, on: date)
        }
        if let cost = posting.cost, let costCurrency = mapper.currency(of: cost.commodity) {
            return book.convert(cost.quantity, from: costCurrency, to: currency, on: date)
        }
        if let price = book.price(of: symbol, on: date), let priceCurrency = mapper.currency(of: price.commodity) {
            return book.convert(posting.amount.quantity * price.quantity, from: priceCurrency, to: currency, on: date)
        }
        return nil
    }

    // MARK: - Snapshots

    /// The dates valuations are written on, from the first activity through
    /// the end of the period holding the journal's last transaction.
    static func periodEnds(_ frequency: LedgerSnapshotFrequency, from first: CalendarDate,
                           through last: CalendarDate) -> [CalendarDate] {
        let months = frequency == .quarter ? 3 : 1
        func periodEnd(_ date: CalendarDate) -> CalendarDate {
            let month = ((date.month - 1) / months + 1) * months
            return YearMonth(year: date.year, month: month)!.lastDay
        }
        var dates: [CalendarDate] = []
        var date = periodEnd(first)
        let end = periodEnd(last)
        while date <= end {
            dates.append(date)
            date = periodEnd(date.adding(days: 1))
        }
        return dates
    }

    private mutating func snapshots(of id: AccountID) {
        guard let accountEvents = events[id], let first = accountEvents.first?.date,
              let journalEnd = journal.lastDate else { return }
        let currency = currency(of: id)
        let holdsInstruments = accountEvents.contains { !$0.quantities.isEmpty }
        let holdsCash = accountEvents.contains { !$0.cash.isEmpty }
        let isHoldings = holdsInstruments || account(id)?.valuationMode == .holdings

        // Where the balance reaches zero and stays there.
        var state = Holdings()
        var zeroSince: CalendarDate?
        for event in accountEvents {
            state.apply(event)
            if state.isZero {
                zeroSince = zeroSince ?? event.date
            } else {
                zeroSince = nil
            }
        }
        if let zeroSince, zeroSince.adding(days: Self.closingDelay) <= journalEnd, until.map({ zeroSince <= $0 }) ?? true {
            closings[id] = zeroSince
        }

        var dates: [CalendarDate]
        if settings.effectiveFrequency == .activity {
            dates = Array(Set(accountEvents.map(\.date))).sorted()
        } else {
            dates = Self.periodEnds(settings.effectiveFrequency, from: first, through: journalEnd)
        }
        if let closing = closings[id] { dates = dates.filter { $0 < closing } + [closing] }
        if let until { dates = dates.filter { $0 <= until } }

        state = Holdings()
        var index = 0
        for date in dates {
            var flow: Decimal? = 0
            while index < accountEvents.count, accountEvents[index].date <= date {
                let event = accountEvents[index]
                state.apply(event)
                flow = flow.flatMap { total in event.flow.map { total + $0 } }
                index += 1
            }
            var record = ImportedRecord(key: .valuation(ValuationKey(account: id, date: date)))
            record.source = .ledger
            record.liabilitySign = .asWritten
            record.flow = flow?.ledgerRounded(2)
            var cash: Decimal = 0
            for (code, quantity) in state.cash.sorted(by: { $0.key < $1.key }) where quantity != 0 {
                if code == currency {
                    cash += quantity
                } else if let converted = book.convert(quantity, from: code, to: currency, on: date) {
                    cash += converted.ledgerRounded(2)
                } else {
                    notes.append(LedgerDiagnostic(
                        .warning, "\(LedgerAmount(quantity, code.rawValue)) in \(account(id)?.name ?? id.rawValue) on "
                            + "\(date) can't be converted to \(currency.rawValue): there's no P rate for it. It was "
                            + "left out."))
                }
            }
            if isHoldings {
                record.positions = state.quantities.filter { $0.value != 0 }.sorted { $0.key < $1.key }.map {
                    let cost = $0.value > 0 ? (state.costs[$0.key] ?? nil) : nil
                    return ImportedPosition(instrument: $0.key, quantity: $0.value, costBasis: cost?.ledgerRounded(2))
                }
                if holdsCash || record.positions.isEmpty { record.cash = cash }
            } else {
                record.balance = cash
            }
            records.append(record)
        }
    }

    // MARK: - Prices

    private mutating func prices() {
        var prices: [PriceKey: (price: Decimal, currency: CurrencyCode)] = [:]
        var rates: [FXKey: Decimal] = [:]
        if settings.effectiveTransactionPrices {
            for transaction in journal.transactions {
                for posting in transaction.postings {
                    guard let unit = posting.unitPrice, let instrument = mapper.instrument(of: posting.amount.commodity),
                          let code = mapper.currency(of: unit.commodity) else { continue }
                    prices[PriceKey(instrument: instrument, date: transaction.date)] = (unit.quantity, code)
                }
            }
        }
        var skipped = Set<String>()
        for price in journal.prices {
            if case .ignored? = mapper.commodities[price.commodity]?.mapping { continue }
            if let instrument = mapper.existingInstrument(forPriced: price.commodity) {
                guard let code = mapper.currency(of: price.price.commodity) else {
                    if skipped.insert(price.commodity).inserted {
                        notes.append(LedgerDiagnostic(
                            .note, "Prices of \(price.commodity) in \(price.price.commodity), which isn't a currency, "
                                + "were left out.", at: price.location))
                    }
                    continue
                }
                prices[PriceKey(instrument: instrument, date: price.date)] = (price.price.quantity, code)
            } else if let base = mapper.currency(of: price.commodity), let quote = mapper.currency(of: price.price.commodity),
                      base != quote {
                rates[FXKey(base: base, quote: quote, date: price.date)] = price.price.quantity
            }
        }
        for (key, value) in prices where until.map({ key.date <= $0 }) ?? true {
            var record = ImportedRecord(key: .price(key), price: value.price, currency: value.currency)
            record.source = .ledger
            records.append(record)
        }
        for (key, rate) in rates where until.map({ key.date <= $0 }) ?? true {
            var record = ImportedRecord(key: .fx(key), rate: rate)
            record.source = .ledger
            records.append(record)
        }
    }
}

extension Decimal {
    /// Rounded half away from zero to `places` fractional digits.
    func ledgerRounded(_ places: Int) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, places, .plain)
        return result
    }
}
