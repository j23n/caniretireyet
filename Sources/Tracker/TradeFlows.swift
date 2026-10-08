import Foundation
import Model

/// Money or securities moving into (+) or out of (−) an account whose
/// holdings come from its trades: its flows (PROGRESS.md; docs/TRADES.md,
/// "Flows"). Amounts are in the account's currency.
///
/// - a deposit or withdrawal: its cash effect;
/// - a transfer in or out, or an opening: the units' market value on its date;
/// - a buy, sell, fee or tax settled outside the account
///   (``Model/Trade/isSettledExternally``): −its amount, i.e. a buy's cost
///   is money added and a sale's proceeds are money taken out;
/// - a **residual**: a valuation's typed cash minus the cash the trades
///   give on its date, treated as deposits or withdrawals nobody recorded.
///
/// Buys, sells, dividends, interest, fees and taxes paid from or into the
/// account's cash are not flows: they move money within the account, or
/// are its return.
public struct TradeFlow: Hashable, Sendable {
    public let date: CalendarDate
    /// In the account's currency; `nil` when a transfer's market value
    /// can't be worked out (no price or FX rate on or before its date), a
    /// deposit has no amount, or a trade settled outside the account has
    /// an amount that can't be worked out (no FX rate).
    public let amount: Decimal?
    /// The deposit, withdrawal, transfer, opening, or trade settled outside
    /// the account; `nil` for a residual.
    public let trade: Trade?
    /// For a residual: since when it could have arisen, the date of the
    /// account's previous valuation with cash (or its opening).
    public let since: CalendarDate?
}

/// The recorded part of a trades account's flow for one valuation, split as
/// a check-in shows it (``Valuator/tradeFlowParts(of:on:previous:)``).
/// Amounts are in the account's currency.
public struct TradeFlowParts: Hashable, Sendable {
    /// What the trades record in the period: deposits, withdrawals,
    /// transfers, openings and trades settled outside the account; `nil`
    /// when one of them can't be valued.
    public var recorded: Decimal?
    /// The part of ``recorded`` from trades settled outside the account
    /// (buys' costs in, sales' proceeds out); those that can't be valued
    /// count as zero.
    public var paidOutside: Decimal

    public init(recorded: Decimal?, paidOutside: Decimal) {
        self.recorded = recorded
        self.paidOutside = paidOutside
    }
}

extension Valuator {
    /// The flows of a trades account dated after `start` (from the
    /// beginning when `nil`) through `end`, sorted by date: its deposits,
    /// withdrawals, transfers, openings and trades settled outside it, and
    /// the residual of each of its valuations with cash (when not zero).
    /// Empty for other accounts.
    public func tradeFlows(of account: AccountID, after start: CalendarDate?, through end: CalendarDate) -> [TradeFlow] {
        guard let ledger = ledgers[account], let details = accounts[account] else { return [] }
        var flows: [TradeFlow] = []
        for entry in ledger.entries(after: start, through: end) where entry.trade.isFlow {
            flows.append(TradeFlow(date: entry.date, amount: flowAmount(of: entry, in: details), trade: entry.trade,
                                   since: nil))
        }
        for valuation in valuations(for: account) where valuation.cash != nil && valuation.date <= end {
            if let start, valuation.date <= start { continue }
            let anchor = cashAnchor(for: account, onOrBefore: valuation.date.adding(days: -1))
            guard let residual = residual(of: valuation, from: anchor), residual != 0 else { continue }
            let since = anchor?.date ?? min(ledger.firstDate ?? details.opened, details.opened)
            flows.append(TradeFlow(date: valuation.date, amount: residual, trade: nil, since: since))
        }
        return flows.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }

    /// The flow of `valuation` of a trades account since `previous`, the
    /// account's valuation before it: the deposits, withdrawals, transfers,
    /// openings and trades settled outside the account dated after
    /// `previous` through the valuation, plus the valuation's residual (its
    /// cash minus the cash the trades give, when it records cash). `nil`
    /// when a transfer can't be valued.
    ///
    /// An account whose history is only trades has no valuation before its
    /// first check-in; its flow then counts from the library's previous
    /// check-in, the period the check-in covers, not from its first trade.
    /// Otherwise every purchase since the account began would count as new
    /// money in that one check-in.
    func tradeFlow(for valuation: Valuation, previous: Valuation?) -> Decimal? {
        guard ledgers[valuation.account] != nil,
              var total = tradeFlowParts(of: valuation.account, on: valuation.date, previous: previous).recorded
        else { return nil }
        if valuation.cash != nil {
            let anchor = previous?.cash != nil
                ? previous : previous.flatMap { cashAnchor(for: valuation.account, onOrBefore: $0.date) }
            total += residual(of: valuation, from: anchor) ?? 0
        }
        return total
    }

    /// The recorded part of the flow of a trades account's valuation on
    /// `date`, `previous` being the account's valuation before it, split
    /// into what was paid from or into another account: the period starts
    /// where ``defaultFlow(for:previous:paid:)`` starts it (`previous`, or
    /// without one the library's previous check-in), so the parts add up to
    /// the flow a check-in saves, residual aside. Zero for other accounts.
    public func tradeFlowParts(of account: AccountID, on date: CalendarDate, previous: Valuation?) -> TradeFlowParts {
        guard let ledger = ledgers[account], let details = accounts[account] else {
            return TradeFlowParts(recorded: 0, paidOutside: 0)
        }
        let start = previous?.date ?? previousCheckIn(before: date)
        var recorded: Decimal? = 0
        var paidOutside: Decimal = 0
        for entry in ledger.entries(after: start, through: date) where entry.trade.isFlow {
            let amount = flowAmount(of: entry, in: details)
            recorded = recorded.flatMap { total in amount.map { total + $0 } }
            if entry.trade.isSettledExternally { paidOutside += amount ?? 0 }
        }
        return TradeFlowParts(recorded: recorded, paidOutside: paidOutside)
    }

    /// `valuation`'s cash minus the cash the trades give on its date,
    /// counting from `anchor`; `nil` when it records no cash.
    func residual(of valuation: Valuation, from anchor: Valuation?) -> Decimal? {
        valuation.cash.map { $0 - derivedCash(of: valuation.account, on: valuation.date, from: anchor) }
    }

    /// A flow trade's amount in the account's currency: a deposit's or
    /// withdrawal's cash effect, a transfer's or opening's market value on
    /// its date (negative for a transfer out), or −the amount of a trade
    /// settled outside the account.
    func flowAmount(of entry: TradeEntry, in account: Account) -> Decimal? {
        let trade = entry.trade
        if trade.isSettledExternally { return entry.externalFlow }
        switch trade.type {
        case .deposit, .withdrawal:
            return entry.cashEffect
        default:
            guard let instrument = trade.instrument, let quantity = trade.quantity else { return nil }
            let value = marketValue(of: quantity, of: instrument, in: account.currency, on: trade.date)
            return trade.type.removesUnits ? value.map { -$0 } : value
        }
    }

    /// The flows of a trades account after `from` through `through`, each
    /// converted into the base currency at its date; `nil` when one is
    /// unknown or can't be converted (reported in `problems`).
    func tradeFlowsInBaseCurrency(of account: Account, after from: CalendarDate, through: CalendarDate,
                                  problems: inout [ValuationProblem]) -> [(date: CalendarDate, amount: Decimal,
                                                                           flow: TradeFlow)]? {
        convertedTradeFlows(of: account, after: from, through: through, to: baseCurrency, problems: &problems)
    }

    /// The flows of a trades account after `from` through `through`, each
    /// converted into `target` at its date (no conversion for the account's
    /// own currency); `nil` when one is unknown or can't be converted
    /// (reported in `problems`).
    func convertedTradeFlows(of account: Account, after from: CalendarDate, through: CalendarDate,
                             to target: CurrencyCode, problems: inout [ValuationProblem])
        -> [(date: CalendarDate, amount: Decimal, flow: TradeFlow)]? {
        var result: [(date: CalendarDate, amount: Decimal, flow: TradeFlow)] = []
        var known = true
        for flow in tradeFlows(of: account.id, after: from, through: through) {
            guard let amount = flow.amount else {
                if let trade = flow.trade, trade.isSettledExternally {
                    // Its amount needs a rate to convert its price.
                    let from = trade.priceCurrency(instruments: instruments, accountCurrency: account.currency)
                    problems.appendIfNew(.missingFX(account: account.id, from: from, to: account.currency))
                } else if let instrument = flow.trade?.instrument {
                    problems.appendIfNew(.missingPrice(account: account.id, instrument: instrument))
                }
                known = false
                continue
            }
            if let value = converted(amount, from: account.currency, to: target, on: flow.date, for: account.id,
                                     problems: &problems) {
                result.append((flow.date, value, flow))
            } else {
                known = false
            }
        }
        return known ? result : nil
    }
}
