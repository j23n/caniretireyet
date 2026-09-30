import Foundation
import Model

/// Money or securities moving into (+) or out of (−) an account whose
/// holdings come from its trades: its flows (PROGRESS.md; docs/TRADES.md,
/// "Flows"). Amounts are in the account's currency.
///
/// - a deposit or withdrawal: its cash effect;
/// - a transfer in or out, or an opening: the units' market value on its date;
/// - a **residual**: a valuation's typed cash minus the cash the trades
///   give on its date, treated as deposits or withdrawals nobody recorded.
///
/// Buys, sells, dividends, interest, fees and taxes are not flows: they
/// move money within the account, or are its return.
public struct TradeFlow: Hashable, Sendable {
    public let date: CalendarDate
    /// In the account's currency; `nil` when a transfer's market value
    /// can't be worked out (no price or FX rate on or before its date) or
    /// a deposit has no amount.
    public let amount: Decimal?
    /// The deposit, withdrawal, transfer or opening; `nil` for a residual.
    public let trade: Trade?
    /// For a residual: the valuation whose cash differs from the trades'.
    public let valuation: Valuation?
    /// For a residual: since when it could have arisen, the date of the
    /// account's previous valuation with cash (or its opening).
    public let since: CalendarDate?

    /// Whether this is a residual rather than a recorded trade.
    public var isResidual: Bool { valuation != nil }
}

extension Valuator {
    /// The flows of a trades account dated after `start` (from the
    /// beginning when `nil`) through `end`, sorted by date: its deposits,
    /// withdrawals, transfers and openings, and the residual of each of
    /// its valuations with cash (when not zero). Empty for other accounts.
    public func tradeFlows(of account: AccountID, after start: CalendarDate?, through end: CalendarDate) -> [TradeFlow] {
        guard let ledger = ledgers[account], let details = accounts[account] else { return [] }
        var flows: [TradeFlow] = []
        for entry in ledger.entries(after: start, through: end) where entry.type.isFlow {
            flows.append(TradeFlow(date: entry.date, amount: flowAmount(of: entry, in: details), trade: entry.trade,
                                   valuation: nil, since: nil))
        }
        for valuation in valuations(for: account) where valuation.cash != nil && valuation.date <= end {
            if let start, valuation.date <= start { continue }
            let anchor = cashAnchor(for: account, onOrBefore: valuation.date.adding(days: -1))
            guard let residual = residual(of: valuation, from: anchor), residual != 0 else { continue }
            let since = anchor?.date ?? min(ledger.firstDate ?? details.opened, details.opened)
            flows.append(TradeFlow(date: valuation.date, amount: residual, trade: nil, valuation: valuation,
                                   since: since))
        }
        return flows.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }

    /// The sum of ``tradeFlows(of:after:through:)``, in the account's
    /// currency; `nil` when one of them is unknown, or for other accounts.
    public func tradeFlowTotal(of account: AccountID, after start: CalendarDate?,
                               through end: CalendarDate) -> Decimal? {
        guard ledgers[account] != nil else { return nil }
        var total: Decimal = 0
        for flow in tradeFlows(of: account, after: start, through: end) {
            guard let amount = flow.amount else { return nil }
            total += amount
        }
        return total
    }

    /// The flow of `valuation` of a trades account since `previous`, the
    /// account's valuation before it: the deposits, withdrawals, transfers
    /// and openings dated after `previous` through the valuation, plus the
    /// valuation's residual (its cash minus the cash the trades give, when
    /// it records cash). `nil` when a transfer can't be valued.
    func tradeFlow(for valuation: Valuation, previous: Valuation?) -> Decimal? {
        guard let ledger = ledgers[valuation.account], let account = accounts[valuation.account] else { return nil }
        var total: Decimal = 0
        for entry in ledger.entries(after: previous?.date, through: valuation.date) where entry.type.isFlow {
            guard let amount = flowAmount(of: entry, in: account) else { return nil }
            total += amount
        }
        if valuation.cash != nil {
            let anchor = previous?.cash != nil
                ? previous : previous.flatMap { cashAnchor(for: valuation.account, onOrBefore: $0.date) }
            total += residual(of: valuation, from: anchor) ?? 0
        }
        return total
    }

    /// `valuation`'s cash minus the cash the trades give on its date,
    /// counting from `anchor`; `nil` when it records no cash.
    func residual(of valuation: Valuation, from anchor: Valuation?) -> Decimal? {
        valuation.cash.map { $0 - derivedCash(of: valuation.account, on: valuation.date, from: anchor) }
    }

    /// A flow trade's amount in the account's currency: a deposit's or
    /// withdrawal's cash effect, or a transfer's or opening's market value
    /// on its date (negative for a transfer out).
    func flowAmount(of entry: TradeEntry, in account: Account) -> Decimal? {
        let trade = entry.trade
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
        var result: [(date: CalendarDate, amount: Decimal, flow: TradeFlow)] = []
        var known = true
        for flow in tradeFlows(of: account.id, after: from, through: through) {
            guard let amount = flow.amount else {
                if let instrument = flow.trade?.instrument {
                    let problem = ValuationProblem.missingPrice(account: account.id, instrument: instrument)
                    if !problems.contains(problem) { problems.append(problem) }
                }
                known = false
                continue
            }
            if amount == 0 || account.currency == baseCurrency {
                result.append((flow.date, amount, flow))
            } else if let converted = fx.convert(amount, from: account.currency, to: baseCurrency, on: flow.date) {
                result.append((flow.date, converted, flow))
            } else {
                let problem = ValuationProblem.missingFX(account: account.id, from: account.currency, to: baseCurrency)
                if !problems.contains(problem) { problems.append(problem) }
                known = false
            }
        }
        return known ? result : nil
    }
}
