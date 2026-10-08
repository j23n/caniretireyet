import Foundation
import Model

// Converting an account between snapshots (balances, or positions at each
// valuation) and trades (docs/TRADES.md, "Converting an account"). The
// functions are pure: they return the records to write, so the app and the
// CLI can preview the change, back up the files it touches, and apply it.

/// Something a conversion had to estimate, or couldn't keep.
public struct ConversionNote: Hashable, Sendable, CustomStringConvertible {
    public struct Kind: OpenEnum {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// An opening without a recorded cost: its cost is its market value on the date.
        public static let costFromMarketValue: Kind = "costFromMarketValue"
        /// An opening without a recorded cost or a price: its cost is unknown.
        public static let unknownCost: Kind = "unknownCost"
        /// A buy or sell priced at the valuation date's price (or the latest
        /// before it), since the real price isn't known.
        public static let priceFromValuation: Kind = "priceFromValuation"
        /// A buy or sell without a price on or before its date or a known
        /// cost: written without price or amount, so its cash effect is unknown.
        public static let noPrice: Kind = "noPrice"
        /// A balance became cash (less the market value of the holdings,
        /// once there are some).
        public static let cashFromBalance: Kind = "cashFromBalance"
        /// The account already had trades, which will count too.
        public static let existingTrades: Kind = "existingTrades"
        /// A valuation added on the date of a month's last trade, so the
        /// history keeps what the trades did.
        public static let addedValuation: Kind = "addedValuation"
        /// The trades were removed: their income, fees and realised gains
        /// are no longer recorded.
        public static let tradesRemoved: Kind = "tradesRemoved"
        /// The account never held cash, so its buys and sales are paid
        /// from or into another account (`"settlement": "external"`).
        public static let settledOutside: Kind = "settledOutside"

        public static let knownValues: [Kind] = [
            .costFromMarketValue, .unknownCost, .priceFromValuation, .noPrice, .cashFromBalance, .existingTrades,
            .addedValuation, .tradesRemoved, .settledOutside,
        ]
    }

    public let kind: Kind
    public let date: CalendarDate
    public let instrument: InstrumentID?
    /// What was done, in plain words.
    public let message: String

    public var description: String { "\(date): \(message)" }
}

/// The records that convert one account between snapshots and trades
/// (``Model/Library/conversionToTrades(of:)``, ``Model/Library/conversionToSnapshots(of:)``).
public struct AccountConversion: Hashable, Sendable {
    /// The account as it will be, with its new `valuation` mode.
    public let account: Account
    /// The account's valuations as they will be: they replace the ones
    /// with the same key, and are added where there's none.
    public let valuations: [Valuation]
    /// Trades to add, sorted by key.
    public let trades: [Trade]
    /// Trades to remove, sorted by key.
    public let removedTrades: [Trade]
    /// What had to be estimated or couldn't be kept, sorted by date.
    public let notes: [ConversionNote]

    /// The months whose history files the conversion changes, sorted.
    public var months: [YearMonth] {
        Set(valuations.map(\.date.yearMonth) + trades.map(\.date.yearMonth) + removedTrades.map(\.date.yearMonth))
            .sorted()
    }

    /// Writes the conversion into `library`.
    public func apply(to library: inout Library) {
        library.accounts[account.id] = account
        for trade in removedTrades { library.removeTradeRecord(trade.key) }
        for valuation in valuations { library.upsert(valuation) }
        for trade in trades { library.upsert(trade) }
    }
}

extension Library {
    // MARK: - Snapshots → trades

    /// The records that make `account` record trades (docs/TRADES.md,
    /// "Converting an account"); `nil` if there's no such account, or it
    /// already records trades.
    ///
    /// - The first valuation with positions gets an `opening` per position:
    ///   its cost is the position's `costBasis`, else its market value on
    ///   the date (noted).
    /// - Each later change in quantity becomes a `buy` or `sell` on the
    ///   valuation's date at that date's price. A buy's cost comes from the
    ///   cost basis where it says what was paid (the check-in's "paid");
    ///   otherwise the price is an estimate (noted), as it is for sells.
    /// - An account that has never held cash (``hasHeldCash(_:)``: its
    ///   valuations list positions and no cash, like coins or a wallet) and
    ///   has no balances was paid from elsewhere: its buys and sales are
    ///   settled outside it (`"settlement": "external"`, noted), so its cash
    ///   stays at zero and what they cost or brought in is a flow.
    /// - Valuations keep their cash (zero when they had none), flow, note
    ///   and source, and lose their positions. A balance becomes cash, less
    ///   the market value of what the trades hold then (noted).
    /// - There's at most one trade per instrument and date, so trades get
    ///   readable IDs: `opening-vwce`, `buy-vwce`, `sell-vwce`.
    ///
    /// Values and flows stay the same: the trades' cash effects are what the
    /// check-in counted as new money, so each valuation's residual is its
    /// old flow (or, settled outside the account, the trades' amounts are
    /// that flow themselves, and there's no residual).
    public func conversionToTrades(of account: AccountID) -> AccountConversion? {
        guard var details = accounts[account], !details.recordsTrades else { return nil }
        let prices = PriceTable(library: self)
        let fx = FXTable(library: self)
        func marketValue(_ quantity: Decimal, _ instrument: InstrumentID, on date: CalendarDate)
            -> (value: Decimal, price: PriceRecord)? {
            guard let price = prices.latest(for: instrument, onOrBefore: date),
                  let value = fx.convert(quantity * price.price, from: price.currency, to: details.currency, on: date)
            else { return nil }
            return (value.rounded(scale: 2), price)
        }

        var notes: [ConversionNote] = []
        var trades: [Trade] = []
        var written: [Valuation] = []
        var held: [InstrumentID: Position] = [:]
        // One trade per instrument and date, so a readable ID is unique: `buy-vwce`.
        func id(_ type: TradeType, _ instrument: InstrumentID) -> TradeID {
            TradeID(Slug.make(from: "\(type.rawValue) \(instrument)"))
        }
        func note(_ kind: ConversionNote.Kind, _ date: CalendarDate, _ instrument: InstrumentID?, _ message: String) {
            notes.append(ConversionNote(kind: kind, date: date, instrument: instrument, message: message))
        }

        // Paid from outside the account when it never held cash of its own.
        let settlement: TradeSettlement? = hasHeldCash(account)
            || valuations(for: account).contains(where: { $0.balance != nil }) ? nil : .external
        var notedSettlement = false
        func noteSettlement(_ date: CalendarDate) {
            guard settlement == .external, !notedSettlement else { return }
            notedSettlement = true
            note(.settledOutside, date, nil, "\(account) has never held cash, so its buys and sales are paid from "
                + "and into another account: its cash stays at zero, and what they cost or brought in is new money.")
        }

        let existing = self.trades(for: account)
        if let first = existing.first {
            note(.existingTrades, first.date, nil, "\(account) already has \(existing.count) trade"
                + "\(existing.count == 1 ? "" : "s"), which will count too. Check them, or remove them.")
        }

        for valuation in valuations(for: account) {
            var converted = valuation
            converted.positions = []
            if let balance = valuation.balance {
                // A balance can't say what's held: it all becomes cash, less what the trades hold.
                var holdings: Decimal = 0
                var priced = true
                for position in held.values where position.quantity != 0 {
                    if let value = marketValue(position.quantity, position.instrument, on: valuation.date)?.value {
                        holdings += value
                    } else {
                        priced = false
                    }
                }
                converted.balance = nil
                converted.cash = balance - holdings
                let rest = holdings == 0 ? "" : ", less \(holdings.fileString) for the holdings"
                note(.cashFromBalance, valuation.date, nil, "The balance of \(balance.fileString) became cash\(rest)"
                    + (priced ? "." : "; some holdings have no price, so the cash is too high."))
                written.append(converted)
                continue
            }
            converted.cash = valuation.cash ?? 0
            // Positions at the account's first valuation are openings; later ones were bought.
            let isFirst = written.isEmpty
            var instruments = valuation.positions.map(\.instrument)
            for instrument in held.keys.sorted() where !instruments.contains(instrument) {
                instruments.append(instrument)
            }
            for instrument in instruments {
                let position = valuation.position(for: instrument)
                let now = position?.quantity ?? 0
                let before = held[instrument]
                let change = now - (before?.quantity ?? 0)
                guard change != 0 else { continue }
                let market = marketValue(abs(change), instrument, on: valuation.date)
                let priceNote = market.map { $0.price.date == valuation.date ? "" : " (the price of \($0.price.date))" }
                    ?? ""
                if isFirst {
                    var cost = position?.costBasis
                    if cost == nil, let market {
                        cost = market.value
                        note(.costFromMarketValue, valuation.date, instrument, "The opening of \(now.fileString) "
                            + "\(instrument) has no recorded cost: it's their value then, \(market.value.fileString)"
                            + "\(priceNote).")
                    } else if cost == nil {
                        note(.unknownCost, valuation.date, instrument, "The opening of \(now.fileString) "
                            + "\(instrument) has no recorded cost and no price, so its cost is unknown.")
                    }
                    trades.append(Trade(account: account, date: valuation.date,
                                        id: id(.opening, instrument), type: .opening,
                                        instrument: instrument, quantity: now, cost: cost, source: valuation.source))
                } else if change > 0 {
                    noteSettlement(valuation.date)
                    let paid = position.flatMap { CheckInRow.paid(for: $0, previous: before) }
                    if paid == nil {
                        if market == nil {
                            note(.noPrice, valuation.date, instrument, "The buy of \(change.fileString) \(instrument) "
                                + "has no price on or before the date and no recorded cost: add its amount.")
                        } else {
                            note(.priceFromValuation, valuation.date, instrument, "The buy of \(change.fileString) "
                                + "\(instrument) is priced at the valuation's price\(priceNote).")
                        }
                    }
                    trades.append(Trade(account: account, date: valuation.date,
                                        id: id(.buy, instrument), type: .buy, instrument: instrument,
                                        quantity: change, price: market?.price.price,
                                        currency: market.map { $0.price.currency },
                                        amount: paid.map { -$0 }, source: valuation.source, settlement: settlement))
                } else {
                    noteSettlement(valuation.date)
                    let sold = 0 - change
                    if market == nil {
                        note(.noPrice, valuation.date, instrument, "The sale of \(sold.fileString) \(instrument) "
                            + "has no price on or before the date: add its amount.")
                    } else {
                        note(.priceFromValuation, valuation.date, instrument, "The sale of \(sold.fileString) "
                            + "\(instrument) is priced at the valuation's price\(priceNote).")
                    }
                    trades.append(Trade(account: account, date: valuation.date,
                                        id: id(.sell, instrument), type: .sell, instrument: instrument,
                                        quantity: sold, price: market?.price.price,
                                        currency: market.map { $0.price.currency }, source: valuation.source,
                                        settlement: settlement))
                }
            }
            for instrument in instruments {
                let quantity = valuation.position(for: instrument)?.quantity ?? 0
                held[instrument] = quantity == 0
                    ? nil : Position(instrument: instrument, quantity: quantity,
                                     costBasis: valuation.position(for: instrument)?.costBasis)
            }
            written.append(converted)
        }

        details.valuation = .trades
        return AccountConversion(account: details, valuations: written, trades: trades.sortedByKey(),
                                 removedTrades: [], notes: notes.sorted { $0.date < $1.date })
    }

    // MARK: - Trades → snapshots

    /// The records that make `account` record positions again (docs/TRADES.md,
    /// "Converting an account"); `nil` if there's no such account, or it
    /// doesn't record trades.
    ///
    /// Each valuation gets the positions and average cost the trades give
    /// on its date, and its cash by the cash rule; it keeps its flow. A
    /// month whose last trade comes after its last valuation gets a
    /// valuation on that trade's date (noted), so values on valuation dates
    /// and month ends stay the same (between them, a snapshot carries the
    /// one before); it, and the valuation after it, get the flow the trades
    /// give. The trades are removed (noted): their income and realised gains
    /// are no longer recorded.
    public func conversionToSnapshots(of account: AccountID) -> AccountConversion? {
        guard var details = accounts[account], details.recordsTrades else { return nil }
        let valuator = Valuator(library: self)
        let ledger = valuator.ledger(for: account)
        let trades = self.trades(for: account)
        let existing = valuations(for: account)
        var notes: [ConversionNote] = []

        // The dates to keep a snapshot on: every valuation's, and each month's last trade after its valuations.
        var dates = Set(existing.map(\.date))
        for (_, monthTrades) in Dictionary(grouping: trades, by: \.date.yearMonth) {
            guard let last = monthTrades.map(\.date).max() else { continue }
            if !existing.contains(where: { $0.date.yearMonth == last.yearMonth && $0.date >= last }) {
                dates.insert(last)
                notes.append(ConversionNote(kind: .addedValuation, date: last, instrument: nil,
                                            message: "A valuation is added on \(last), the last trade of its month, "
                                                + "so the history keeps what the trades did."))
            }
        }

        var valuations: [Valuation] = []
        var previousOld: Valuation?
        var previousNew: Valuation?
        for date in dates.sorted() {
            let old = existing.first { $0.date == date }
            var snapshot = old ?? Valuation(account: account, date: date)
            snapshot.balance = nil
            snapshot.cash = valuator.tradeCash(of: account, on: date)
            snapshot.positions = ledger?.positions(on: date) ?? []
            if let old, previousOld?.date == previousNew?.date {
                snapshot.flow = old.flow
            } else {
                // Added, or a valuation was added before it: its flow since then, from the trades.
                snapshot.flow = valuator.defaultFlow(for: old ?? snapshot, previous: previousNew) ?? old?.flow
            }
            if old != nil { previousOld = old }
            previousNew = snapshot
            valuations.append(snapshot)
        }
        if let first = trades.first {
            notes.append(ConversionNote(kind: .tradesRemoved, date: first.date, instrument: nil,
                                        message: "\(trades.count) trade\(trades.count == 1 ? " is" : "s are") removed: "
                                            + "their income, fees and realised gains are no longer recorded."))
        }

        details.valuation = details.kind.defaultValuationMode == .holdings ? nil : .holdings
        return AccountConversion(account: details, valuations: valuations, trades: [], removedTrades: trades,
                                 notes: notes.sorted { $0.date < $1.date })
    }

    /// Converts `account` to trades (``conversionToTrades(of:)``) and
    /// returns what was done; `nil`, changing nothing, when it can't be.
    @discardableResult
    public mutating func convertToTrades(_ account: AccountID) -> AccountConversion? {
        let conversion = conversionToTrades(of: account)
        conversion?.apply(to: &self)
        return conversion
    }
}
