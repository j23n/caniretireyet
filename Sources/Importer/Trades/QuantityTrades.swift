import Foundation
import Model

// Quantities imported into an account that records trades become trades
// (IMPORT.md, "Quantities in a trades account"), worked out with Model's
// `HeldQuantities`.

extension PreviewBuilder {
    /// Turns the quantities and purchase costs of accounts that record
    /// trades into trades (``QuantityTrades``), appended to ``trades``. Their
    /// positions leave `accumulators`, whose records keep only their balance
    /// and cash. A purchase cost without a quantity on its date is a cell
    /// problem: a trades account's values hold no positions to add it to.
    ///
    /// Returns the records as the file gave them, positions included, so
    /// closings are still proposed from the dates of their values.
    mutating func convertQuantitiesToTrades(_ accumulators: inout [ImportRecordKey: Accumulator]) -> [ImportedRecord] {
        var byAccount: [AccountID: [ImportRecordKey]] = [:]
        for (key, accumulator) in accumulators {
            guard case .valuation(let valuation) = key, !accumulator.record.positions.isEmpty,
                  accounts[valuation.account]?.recordsTrades == true
            else { continue }
            byAccount[valuation.account, default: []].append(key)
        }
        guard !byAccount.isEmpty else { return [] }
        let market = MarketData(library: library, file: accumulators.values.map(\.record))
        var original: [ImportedRecord] = []
        for (accountID, keys) in byAccount.sorted(by: { $0.key < $1.key }) {
            guard let account = accounts[accountID] else { continue }
            var rows: [QuantityTrades.Row] = []
            for key in keys.sorted() {
                guard var accumulator = accumulators[key] else { continue }
                original.append(accumulator.record)
                var row = QuantityTrades.Row(date: key.date)
                for position in accumulator.record.positions {
                    guard position.quantity != nil else {
                        failCost(accumulator, position.instrument)
                        continue
                    }
                    row.positions.append(position)
                    row.cells[position.instrument] = [RecordField.quantity(position.instrument),
                                                      .costBasis(position.instrument)]
                        .compactMap { accumulator.sources[$0]?.cell }
                }
                if !row.positions.isEmpty { rows.append(row) }
                accumulator.record.positions = []
                accumulator.cells = [RecordField.balance, .cash].compactMap { accumulator.sources[$0]?.cell }
                accumulators[key] = accumulator
            }
            let fileHasCash = accumulators.contains { key, accumulator in
                key.account == accountID && ((accumulator.record.cash ?? 0) != 0 || accumulator.record.balance != nil)
            }
            let conversion = QuantityTrades(account: account, rows: rows, library: library, market: market,
                                            fileHasCash: fileHasCash)
            trades += conversion.trades.map { (ImportedRecord(trade: $0.trade), $0.cells) }
            tradesFromQuantities.formUnion(conversion.trades.map { .trade($0.trade.key) })
            removedTrades += conversion.removed
            issues += conversion.notes
        }
        return original
    }
}

/// The trades that make an account that records trades hold the quantities
/// a file gives on each date:
///
/// - The account's first row is an `opening` per position when nothing was
///   held before it: its cost is the file's purchase cost, else its market
///   value on the date (the latest price on or before it, in the account's
///   currency).
/// - Then each change from what's held becomes a `buy` or a `sell` on the
///   row's date, at that date's price. A buy's amount is what the purchase
///   cost says was paid (its rise since the file's last row, or all of it
///   when nothing was held), when the file gives it.
/// - What's held comes from the account's trades up to the date (Model's
///   `HeldQuantities`) and those made for earlier rows. An instrument the
///   row doesn't mention is left as it is: the file says nothing about it.
/// - An account that has never held cash (no cash or balance in its values
///   or the file, no deposit, no sale into its cash) has its buys and sales
///   paid from outside it (`"settlement": "external"`).
/// - Trades get the readable IDs the conversion gives (`opening-vwce`,
///   `buy-vwce`, `sell-vwce`), one per instrument and date, so importing the
///   file again finds the same trades. The library's trades with those keys
///   are the ones the file is compared with, so they don't count as held,
///   and those the file no longer makes are ``removed``.
struct QuantityTrades {
    /// The quantities, and purchase costs, the file gives for one date.
    struct Row {
        var date: CalendarDate
        /// Positions with a quantity, sorted by instrument.
        var positions: [ImportedPosition] = []
        /// The cells of each position's quantity and purchase cost.
        var cells: [InstrumentID: [ImportCellRef]] = [:]
    }

    /// The trades made, sorted by date, with the cells they came from.
    private(set) var trades: [(trade: Trade, cells: [ImportCellRef])] = []
    /// The library's trades with the keys of the file's dates and
    /// positions that the file no longer makes, with the cells of their
    /// positions: what's held leaves them out, so applying the trades made
    /// removes them.
    private(set) var removed: [(trade: Trade, cells: [ImportCellRef])] = []
    /// What the conversion estimated, as notes.
    private(set) var notes: [ImportIssue] = []

    /// Makes the trades for `rows` of `account`, which records trades.
    /// `fileHasCash`: the file gives the account cash or a balance.
    init(account: Account, rows: [Row], library: Library, market: MarketData, fileHasCash: Bool) {
        let rows = rows.sorted { $0.date < $1.date }
        let replaced = Set(rows.flatMap { row in
            row.positions.flatMap { position in
                [TradeType.opening, .buy, .sell].map {
                    TradeKey(account: account.id, date: row.date, id: Self.id($0, position.instrument))
                }
            }
        })
        let others = library.trades(for: account.id).filter { !replaced.contains($0.key) }
        let holdsCash = fileHasCash
            || library.valuations(for: account.id).contains { ($0.cash ?? 0) != 0 || $0.balance != nil }
            || others.contains { $0.type == .deposit || ($0.type == .sell && !$0.isSettledExternally) }
        let settlement: TradeSettlement? = holdsCash ? nil : .external

        var unpriced = 0, uncosted = 0
        var previous: [InstrumentID: ImportedPosition] = [:]
        for (index, row) in rows.enumerated() {
            let earlier = others.filter { $0.date <= row.date } + trades.map(\.trade)
            let held = HeldQuantities(earlier)
            // Positions at the account's first row are openings, unless something was held before.
            let isFirst = index == 0 && held.quantities.isEmpty
            for position in row.positions {
                guard let now = position.quantity else { continue }
                let instrument = position.instrument
                let before = held[instrument]
                let change = now - before
                guard change != 0 else { continue }
                let price = market.price(of: instrument, onOrBefore: row.date)
                var trade: Trade
                if isFirst {
                    var cost = position.costBasis
                    if cost == nil, let price {
                        cost = market.convert(now * price.price, from: price.currency, to: account.currency,
                                              on: row.date)?.rounded(scale: 2)
                    }
                    if cost == nil { uncosted += 1 }
                    trade = Trade(account: account.id, date: row.date, id: Self.id(.opening, instrument),
                                  type: .opening, instrument: instrument, quantity: now, cost: cost)
                } else if change > 0 {
                    let paid = Self.paid(position, before: before, previous: previous[instrument])
                    if paid == nil, price == nil { unpriced += 1 }
                    trade = Trade(account: account.id, date: row.date, id: Self.id(.buy, instrument), type: .buy,
                                  instrument: instrument, quantity: change, price: price?.price,
                                  currency: price?.currency, amount: paid.map { 0 - $0 }, settlement: settlement)
                } else {
                    if price == nil { unpriced += 1 }
                    trade = Trade(account: account.id, date: row.date, id: Self.id(.sell, instrument), type: .sell,
                                  instrument: instrument, quantity: 0 - change, price: price?.price,
                                  currency: price?.currency, settlement: settlement)
                }
                trade.source = .import
                trades.append((trade, row.cells[instrument] ?? []))
            }
            for position in row.positions { previous[position.instrument] = position }
        }
        let made = Set(trades.map(\.trade.key))
        let cells = Dictionary(rows.map { ($0.date, $0.cells) }, uniquingKeysWith: { first, _ in first })
        removed = library.trades(for: account.id)
            .filter { replaced.contains($0.key) && !made.contains($0.key) }
            .map { trade in (trade, trade.instrument.flatMap { cells[trade.date]?[$0] } ?? []) }

        guard !trades.isEmpty else { return }
        func count(_ type: TradeType) -> Int { trades.filter { $0.trade.type == type }.count }
        let note = ImportIssue.Kind.quantitiesAsTrades(account.id, openings: count(.opening), buys: count(.buy),
                                                       sales: count(.sell), settledOutside: settlement == .external)
        notes.append(ImportIssue(kind: note))
        if unpriced > 0 { notes.append(ImportIssue(kind: .tradesWithoutPrice(account.id, count: unpriced))) }
        if uncosted > 0 { notes.append(ImportIssue(kind: .openingsWithoutCost(account.id, count: uncosted))) }
    }

    /// `opening-vwce`, `buy-vwce`, `sell-vwce`: the IDs the conversion to trades gives.
    static func id(_ type: TradeType, _ instrument: InstrumentID) -> TradeID {
        TradeID(Slug.make(from: "\(type.rawValue) \(instrument)"))
    }

    /// What a rise in quantity cost, from the purchase cost, as the
    /// check-in's "paid" works it out: all of it when nothing was held,
    /// else its rise since the file's last row of the instrument, when that
    /// row's quantity is what was held. `nil` when it can't be known.
    static func paid(_ position: ImportedPosition, before: Decimal, previous: ImportedPosition?) -> Decimal? {
        guard let cost = position.costBasis else { return nil }
        if before <= 0 { return cost }
        guard let previous, previous.quantity == before, let previousCost = previous.costBasis else { return nil }
        return cost - previousCost
    }
}

/// The prices and FX rates a conversion of quantities into trades looks
/// up: the library's, and the file's, which win on the same date.
struct MarketData {
    private struct Pair: Hashable {
        var base: CurrencyCode
        var quote: CurrencyCode
    }

    private let prices: [InstrumentID: [PriceRecord]]
    private let rates: [Pair: [FXRecord]]

    init(library: Library, file records: [ImportedRecord]) {
        var prices: [PriceKey: PriceRecord] = [:]
        var rates: [FXKey: FXRecord] = [:]
        for month in library.months.values {
            for price in month.prices { prices[price.key] = price }
            for rate in month.fx where rate.rate > 0 { rates[rate.key] = rate }
        }
        for record in records {
            switch record.key {
            case .price(let key):
                guard let price = record.price, let currency = record.currency else { continue }
                prices[key] = PriceRecord(instrument: key.instrument, date: key.date, price: price, currency: currency)
            case .fx(let key):
                guard let rate = record.rate, rate > 0 else { continue }
                rates[key] = FXRecord(base: key.base, quote: key.quote, date: key.date, rate: rate)
            default:
                continue
            }
        }
        self.prices = Dictionary(grouping: prices.values, by: \.instrument).mapValues { $0.sortedByKey() }
        self.rates = Dictionary(grouping: rates.values) { Pair(base: $0.base, quote: $0.quote) }
            .mapValues { $0.sortedByKey() }
    }

    /// The latest price of `instrument` dated on or before `date`.
    func price(of instrument: InstrumentID, onOrBefore date: CalendarDate) -> PriceRecord? {
        guard let records = prices[instrument], let index = records.lastIndex(onOrBefore: date, date: \.date)
        else { return nil }
        return records[index]
    }

    /// `amount` converted from one currency to another at the latest rate
    /// on or before `date`, direct or inverted (the more recent; direct on
    /// a tie); `nil` without one.
    func convert(_ amount: Decimal, from: CurrencyCode, to: CurrencyCode, on date: CalendarDate) -> Decimal? {
        if from == to { return amount }
        let direct = latest(Pair(base: from, quote: to), on: date)
        let inverse = latest(Pair(base: to, quote: from), on: date)
        if let direct, inverse.map({ $0.date <= direct.date }) ?? true { return amount * direct.rate }
        return inverse.map { amount / $0.rate }
    }

    private func latest(_ pair: Pair, on date: CalendarDate) -> FXRecord? {
        guard let records = rates[pair], let index = records.lastIndex(onOrBefore: date, date: \.date) else {
            return nil
        }
        return records[index]
    }
}
