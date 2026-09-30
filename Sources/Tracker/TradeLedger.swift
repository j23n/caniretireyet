import Foundation
import Model

/// One trade as the ledger applied it: its cash effect, and what it did to
/// its instrument's quantity and purchase cost. Amounts are in the
/// account's currency.
public struct TradeEntry: Hashable, Sendable {
    public let trade: Trade
    /// The trade's value before fees and tax: quantity × price, converted
    /// into the account's currency at the latest FX rate on or before the
    /// trade date. `nil` without a quantity and a price, or without a rate.
    public let gross: Decimal?
    /// The conversion used for ``gross``; `nil` when none was needed.
    public let fx: FXQuote?
    /// What the account's cash changed by: `amount` as written, or worked
    /// out from ``gross``, fees and tax (see docs/TRADES.md), rounded to
    /// cents. `nil` when it can't be worked out; the ledger then counts it
    /// as zero and reports an issue.
    public let cashEffect: Decimal?
    /// The purchase cost the trade moved: added by a buy (what it cost,
    /// fees and tax included), an opening or a transfer in (its `cost`);
    /// taken away by a sell or a transfer out (the average cost of the
    /// units, pro rata), as a positive amount. `nil` when unknown or when
    /// the trade doesn't change holdings.
    public let cost: Decimal?
    /// For a sell: proceeds before tax (`amount + tax`, i.e. gross − fees)
    /// minus the average cost of the units sold. `nil` when either is
    /// unknown, or the sell takes away more than was held.
    public let realizedGain: Decimal?
    /// The quantity of the trade's instrument after it; `nil` for trades
    /// that don't change holdings.
    public let quantityAfter: Decimal?
    /// The purchase cost of the instrument's whole position after it;
    /// `nil` when unknown or for trades that don't change holdings.
    public let costAfter: Decimal?

    public var date: CalendarDate { trade.date }
    public var type: TradeType { trade.type }
}

/// An account's trades applied in order (docs/TRADES.md): the quantity and
/// average purchase cost of each instrument on any date, the cash effect of
/// the trades, realised gains and income.
///
/// - Trades apply in processing order (``Model/Swift/Sequence/inProcessingOrder()``):
///   by date, and within a day splits first, buys before sells.
/// - **Average cost** (*costo medio ponderato*), in the account's currency:
///   a buy adds what it cost (−cash effect: price × quantity × FX at the
///   trade date, plus fees and tax); an opening or transfer in adds its
///   `cost`; a sell or transfer out takes away the average cost of the
///   units, pro rata, rounded to cents; a split changes the quantity, not
///   the cost. A position that goes back to zero starts afresh.
/// - A **realised gain** is a sale's proceeds before tax (gross − fees)
///   minus the average cost of the units sold.
///
/// Build one with the account, its trades and the library's FX rates (or
/// take it from ``Valuator/ledger(for:)``); queries by date are binary
/// searches.
public struct TradeLedger: Sendable {
    public let account: AccountID
    /// The account's currency: costs, cash effects and gains are in it.
    public let currency: CurrencyCode
    /// Every trade applied, in processing order.
    public let entries: [TradeEntry]
    /// What was wrong with the trades, in processing order.
    public let issues: [TradeIssue]

    /// One per date with trades: the positions after that day's trades.
    private let days: [(date: CalendarDate, positions: [InstrumentID: PositionState])]
    /// Running sums over ``entries``: cash effects (unknown ones as zero),
    /// and how many were unknown.
    private let cashTotals: [Decimal]
    private let unknownCashCounts: [Int]

    /// The quantity and total cost of one instrument; `cost` is `nil` when unknown.
    struct PositionState: Hashable, Sendable {
        var quantity: Decimal = 0
        var cost: Decimal? = 0
    }

    /// Applies `trades` of `account` (other accounts' trades are ignored).
    /// `instruments` give a price's default currency; `fx` converts prices
    /// into the account's currency at each trade date.
    public init(account: Account, trades: some Sequence<Trade>, instruments: [InstrumentID: Instrument] = [:],
                fx: FXTable) {
        self.account = account.id
        currency = account.currency
        var entries: [TradeEntry] = []
        var issues: [TradeIssue] = []
        var positions: [InstrumentID: PositionState] = [:]
        var days: [(date: CalendarDate, positions: [InstrumentID: PositionState])] = []
        var cashTotals: [Decimal] = []
        var unknownCounts: [Int] = []
        var runningCash: Decimal = 0
        var runningUnknown = 0

        for trade in trades.filter({ $0.account == account.id }).inProcessingOrder() {
            func issue(_ kind: TradeIssue.Kind, _ severity: TradeProblem.Severity, _ message: String) {
                issues.append(TradeIssue(kind, severity, account: account.id, trade: trade.key,
                                         instrument: trade.instrument, date: trade.date,
                                         message: "\(Self.describe(trade)): \(message)"))
            }
            for problem in trade.problems {
                issue(.invalidTrade, problem.severity, problem.message)
            }

            // The value before fees and tax, in the account's currency.
            var gross: Decimal?
            var quote: FXQuote?
            var missingRate = false
            let priceCurrency = trade.currency ?? trade.instrument.flatMap { instruments[$0]?.currency }
                ?? account.currency
            if let quantity = trade.quantity, let price = trade.price {
                if priceCurrency == account.currency {
                    gross = (quantity * price).roundedToCents
                } else if let found = fx.quote(from: priceCurrency, to: account.currency, on: trade.date) {
                    quote = found
                    gross = found.convert(quantity * price).roundedToCents
                } else if trade.amount == nil, Self.cashEffectNeedsGross.contains(trade.type) {
                    missingRate = true
                    issue(.missingFX, .error, "There's no \(priceCurrency)→\(account.currency) rate on or before "
                        + "\(trade.date), so its amount can't be worked out. Add the rate, or the amount.")
                }
            }
            let cashEffect = trade.amount ?? Self.computedCashEffect(of: trade, gross: gross)

            // Holdings and cost.
            var cost: Decimal?
            var gain: Decimal?
            var quantityAfter: Decimal?
            var costAfter: Decimal?
            if trade.type.changesHoldings, let instrument = trade.instrument {
                var state = positions[instrument] ?? PositionState()
                let before = state.quantity
                switch trade.type {
                case .split:
                    if let ratio = trade.ratio, ratio > 0 {
                        if before == 0 {
                            issue(.splitNotHeld, .warning, "The account doesn't hold \(instrument), so the split "
                                + "changes nothing.")
                        }
                        state.quantity = before * ratio
                    }
                case .buy, .opening, .transferIn:
                    guard let quantity = trade.quantity, quantity > 0 else { break }
                    if trade.type == .buy {
                        cost = cashEffect.map { -$0 }
                    } else {
                        cost = trade.cost
                        if cost == nil {
                            issue(.unknownCost, .warning, "It has no cost, so the purchase cost of \(instrument) is "
                                + "unknown until the position is closed. Add its cost (valore di carico).")
                        }
                    }
                    let previousCost: Decimal? = before > 0 ? state.cost : 0
                    state.quantity = before + quantity
                    state.cost = previousCost.flatMap { previous in cost.map { previous + $0 } }
                default:  // sell, transferOut
                    guard let quantity = trade.quantity, quantity > 0 else { break }
                    let held = max(before, 0)
                    if quantity > held {
                        issue(.oversold, .error, "It takes away \((quantity - held).fileString) more than the "
                            + "account held then (\(held.fileString)). Is a buy or an opening missing, or the date "
                            + "wrong?")
                    }
                    let taken = min(quantity, held)
                    if taken == held {
                        cost = held > 0 ? state.cost : 0
                    } else {
                        cost = state.cost.map { ($0 * taken / held).roundedToCents }
                    }
                    state.cost = state.cost.flatMap { total in cost.map { total - $0 } }
                    if before - quantity <= 0 { state.cost = 0 }
                    state.quantity = before - quantity
                    if trade.type == .sell, quantity <= held, let cashEffect, let cost {
                        gain = cashEffect + (trade.tax ?? 0) - cost
                    }
                }
                positions[instrument] = state
                quantityAfter = state.quantity
                costAfter = state.cost
            }

            if cashEffect == nil, trade.type.isKnown, !missingRate,
               !trade.problems.contains(where: { $0.severity == .error }) {
                issue(.invalidTrade, .error, "Its cash effect can't be worked out.")
            }
            runningCash += cashEffect ?? 0
            if cashEffect == nil && trade.type.isKnown { runningUnknown += 1 }
            cashTotals.append(runningCash)
            unknownCounts.append(runningUnknown)
            entries.append(TradeEntry(trade: trade, gross: gross, fx: quote, cashEffect: cashEffect, cost: cost,
                                      realizedGain: gain, quantityAfter: quantityAfter, costAfter: costAfter))
            if days.last?.date == trade.date {
                days[days.count - 1].positions = positions
            } else {
                days.append((trade.date, positions))
            }
        }
        self.entries = entries
        self.issues = issues
        self.days = days
        self.cashTotals = cashTotals
        unknownCashCounts = unknownCounts
    }

    // MARK: - Holdings

    /// The date of the first trade, if any.
    public var firstDate: CalendarDate? { entries.first?.date }

    /// The date of the latest trade, if any.
    public var lastDate: CalendarDate? { entries.last?.date }

    /// The positions held at the end of `date` (its trades included), with
    /// their purchase cost (`nil` when unknown), sorted by instrument.
    /// Instruments back at zero are left out; a negative quantity (more
    /// sold than held) is kept, so the mistake shows.
    public func positions(on date: CalendarDate) -> [Position] {
        guard let index = days.lastIndex(onOrBefore: date, date: \.date) else { return [] }
        return days[index].positions
            .filter { $0.value.quantity != 0 }
            .sorted { $0.key < $1.key }
            .map { Position(instrument: $0.key, quantity: $0.value.quantity, costBasis: $0.value.cost) }
    }

    /// The position in `instrument` at the end of `date`, if the account holds any.
    public func position(of instrument: InstrumentID, on date: CalendarDate) -> Position? {
        positions(on: date).first { $0.instrument == instrument }
    }

    // MARK: - Cash

    /// The sum of the cash effects of the trades dated after `start` (from
    /// the first trade when `nil`) through `end`. Unknown effects count as
    /// zero; see ``unknownCashEffects(after:through:)``.
    public func cashEffect(after start: CalendarDate?, through end: CalendarDate) -> Decimal {
        guard let last = entries.lastIndex(onOrBefore: end, date: \.date) else { return 0 }
        let first = start.flatMap { entries.lastIndex(onOrBefore: $0, date: \.date) }
        if let first, first >= last { return 0 }
        return cashTotals[last] - (first.map { cashTotals[$0] } ?? 0)
    }

    /// How many trades dated after `start` through `end` have a cash effect
    /// that couldn't be worked out.
    public func unknownCashEffects(after start: CalendarDate?, through end: CalendarDate) -> Int {
        guard let last = entries.lastIndex(onOrBefore: end, date: \.date) else { return 0 }
        let first = start.flatMap { entries.lastIndex(onOrBefore: $0, date: \.date) }
        if let first, first >= last { return 0 }
        return unknownCashCounts[last] - (first.map { unknownCashCounts[$0] } ?? 0)
    }

    /// The entries dated after `start` (from the first when `nil`) through `end`.
    public func entries(after start: CalendarDate?, through end: CalendarDate) -> ArraySlice<TradeEntry> {
        let last = entries.lastIndex(onOrBefore: end, date: \.date).map { $0 + 1 } ?? 0
        let first = start.flatMap { entries.lastIndex(onOrBefore: $0, date: \.date) }.map { $0 + 1 } ?? 0
        return first < last ? entries[first..<last] : []
    }

    // MARK: - Years

    /// The years with trades, sorted.
    public var years: [Int] {
        Array(Set(entries.map(\.date.year))).sorted()
    }

    /// Realised gains, income, fees, taxes and money in and out in `year`,
    /// in the account's currency.
    public func summary(for year: Int) -> TradeYearSummary {
        var summary = TradeYearSummary(year: year, currency: currency)
        for entry in entries where entry.date.year == year {
            summary.add(entry, converted: { $0 })
        }
        return summary
    }

    // MARK: - Internals

    /// The types whose cash effect, without an `amount`, comes from quantity × price.
    static let cashEffectNeedsGross: Set<TradeType> = [.buy, .sell, .dividend, .interest]

    /// The cash effect of a trade without an `amount`: see docs/TRADES.md.
    static func computedCashEffect(of trade: Trade, gross: Decimal?) -> Decimal? {
        let fees = trade.fees ?? 0
        let tax = trade.tax ?? 0
        switch trade.type {
        case .buy: return gross.map { -($0 + fees + tax) }
        case .sell, .dividend, .interest: return gross.map { $0 - fees - tax }
        case .fee, .tax: return trade.fees == nil && trade.tax == nil ? nil : -(fees + tax)
        case .deposit, .withdrawal: return nil
        case .transferIn, .transferOut, .opening, .split: return -(fees + tax)
        default: return 0  // Types this version doesn't know are left out.
        }
    }

    /// `The buy of vwce on 2026-03-12 (k3q7vz2m)`
    static func describe(_ trade: Trade) -> String {
        let what = trade.instrument.map { " of \($0)" } ?? ""
        return "The \(trade.type.rawValue)\(what) on \(trade.date) (\(trade.id))"
    }
}

/// A year of an account's (or several accounts') trades, for the tax
/// return and the income view: realised gains, income, fees, taxes, and
/// money in and out. Amounts are in ``currency``.
public struct TradeYearSummary: Hashable, Sendable {
    public let year: Int
    public let currency: CurrencyCode
    /// The sum of the realised gains (negative for losses) of the year's
    /// sales whose gain is known.
    public var realizedGain: Decimal = 0
    /// ``realizedGain`` by instrument.
    public var realizedGainByInstrument: [InstrumentID: Decimal] = [:]
    /// Sales whose gain isn't known (unknown cost or cash effect, or more
    /// sold than held): left out of ``realizedGain``.
    public var salesWithUnknownGain: [TradeKey] = []
    /// Dividends before tax withheld (amount + tax + fees).
    public var dividends: Decimal = 0
    /// ``dividends`` by instrument; dividends without one aren't listed.
    public var dividendsByInstrument: [InstrumentID: Decimal] = [:]
    /// Interest before tax withheld; negative when interest was charged.
    public var interest: Decimal = 0
    /// Every fee: the `fees` of trades, and `fee` trades.
    public var fees: Decimal = 0
    /// Every tax: tax withheld on sales, dividends and interest, a buy's
    /// transaction tax, and `tax` trades (imposta di bollo).
    public var taxes: Decimal = 0
    /// Deposits, positive.
    public var deposits: Decimal = 0
    /// Withdrawals, as a positive amount taken out.
    public var withdrawals: Decimal = 0
    /// Trades whose amounts couldn't be converted into ``currency`` (a
    /// missing FX rate): left out.
    public var unconverted: [TradeKey] = []

    public init(year: Int, currency: CurrencyCode) {
        self.year = year
        self.currency = currency
    }

    /// Dividends and interest after tax withheld.
    public var netIncome: Decimal {
        dividends + interest - incomeTax
    }

    /// The part of ``taxes`` withheld on dividends and interest.
    public private(set) var incomeTax: Decimal = 0

    /// Adds one entry, converting its amounts with `convert` (`nil` when a
    /// rate is missing).
    mutating func add(_ entry: TradeEntry, converted convert: (Decimal) -> Decimal?) {
        let trade = entry.trade
        func value(_ amount: Decimal?) -> Decimal? {
            guard let amount else { return nil }
            if amount == 0 { return 0 }
            guard let converted = convert(amount) else {
                if !unconverted.contains(trade.key) { unconverted.append(trade.key) }
                return nil
            }
            return converted
        }
        let fees = trade.fees ?? 0
        let tax = trade.tax ?? 0
        switch trade.type {
        case .sell:
            if let gain = value(entry.realizedGain) {
                realizedGain += gain
                if let instrument = trade.instrument { realizedGainByInstrument[instrument, default: 0] += gain }
            } else if entry.realizedGain == nil {
                salesWithUnknownGain.append(trade.key)
            }
            self.fees += value(fees) ?? 0
            taxes += value(tax) ?? 0
        case .dividend:
            if let gross = value(entry.cashEffect.map { $0 + tax + fees }) {
                dividends += gross
                if let instrument = trade.instrument { dividendsByInstrument[instrument, default: 0] += gross }
            }
            self.fees += value(fees) ?? 0
            let withheld = value(tax) ?? 0
            taxes += withheld
            incomeTax += withheld
        case .interest:
            interest += value(entry.cashEffect.map { $0 + tax + fees }) ?? 0
            self.fees += value(fees) ?? 0
            let withheld = value(tax) ?? 0
            taxes += withheld
            incomeTax += withheld
        case .fee:
            self.fees += value(entry.cashEffect.map { -$0 - tax }) ?? 0
            taxes += value(tax) ?? 0
        case .tax:
            taxes += value(entry.cashEffect.map { -$0 - fees }) ?? 0
            self.fees += value(fees) ?? 0
        case .deposit:
            deposits += value(entry.cashEffect) ?? 0
        case .withdrawal:
            withdrawals -= value(entry.cashEffect) ?? 0
        default:
            self.fees += value(fees) ?? 0
            taxes += value(tax) ?? 0
        }
    }
}
