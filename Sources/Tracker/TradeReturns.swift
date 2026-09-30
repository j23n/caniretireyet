import Foundation
import Model

/// What one position of a trades account earned over a period, dividends
/// included, in the account's currency (docs/TRADES.md, "Returns").
public struct InstrumentReturn: Hashable, Sendable {
    public let account: AccountID
    public let instrument: InstrumentID
    public let start: CalendarDate
    public let end: CalendarDate
    /// The position's market value at the start and the end; `nil` without a price.
    public let startValue: Decimal?
    public let endValue: Decimal?
    /// Money put into the position (buys with their fees and tax, units
    /// moved in at their market value) less money taken out (sales before
    /// tax withheld, units moved out at their market value). `nil` when a
    /// transfer or a trade's amount can't be valued.
    public let netInvested: Decimal?
    /// Dividends before tax withheld.
    public let dividends: Decimal
    /// Gains realised by sales in the period.
    public let realizedGain: Decimal
    /// `endValue − startValue − netInvested + dividends`: price movement,
    /// realised and not, plus dividends, less fees.
    public let gain: Decimal?
    /// The internal rate of return of the position's money: the start value
    /// and each purchase in, each sale and dividend out, and the end value.
    public let moneyWeighted: ReturnFigure?
}

extension Valuator {
    /// What `instrument` in the trades account `account` earned from `start`
    /// to `end`, dividends included; `nil` unless the account records trades
    /// and `start < end`.
    public func instrumentReturn(of instrument: InstrumentID, in account: AccountID, from start: CalendarDate,
                                 to end: CalendarDate) -> InstrumentReturn? {
        guard start < end, let ledger = ledgers[account], let details = accounts[account] else { return nil }
        func value(on date: CalendarDate) -> Decimal? {
            let quantity = ledger.position(of: instrument, on: date)?.quantity ?? 0
            return marketValue(of: quantity, of: instrument, in: details.currency, on: date)
        }
        let startValue = value(on: start)
        let endValue = value(on: end)
        var invested: Decimal? = 0
        var dividends: Decimal = 0
        var realized: Decimal = 0
        var flows: [DatedAmount] = []
        for entry in ledger.entries(after: start, through: end) where entry.trade.instrument == instrument {
            let trade = entry.trade
            var into: Decimal?
            switch trade.type {
            case .buy:
                into = entry.cashEffect.map { -$0 }
            case .sell:
                into = entry.cashEffect.map { -($0 + (trade.tax ?? 0)) }
                realized += entry.realizedGain ?? 0
            case .transferIn, .opening, .transferOut:
                into = entry.trade.quantity.flatMap {
                    marketValue(of: $0, of: instrument, in: details.currency, on: trade.date)
                }.map { trade.type.removesUnits ? -$0 : $0 }
            case .dividend:
                let gross = (entry.cashEffect ?? 0) + (trade.tax ?? 0) + (trade.fees ?? 0)
                dividends += gross
                flows.append(DatedAmount(date: trade.date, amount: gross))
                continue
            default:
                continue
            }
            guard let into else {
                invested = nil
                continue
            }
            invested = invested.map { $0 + into }
            flows.append(DatedAmount(date: trade.date, amount: -into))
        }
        var gain: Decimal?
        var moneyWeighted: ReturnFigure?
        if let startValue, let endValue, let invested {
            gain = endValue - startValue - invested + dividends
            let all = [DatedAmount(date: start, amount: -startValue)] + flows + [DatedAmount(date: end, amount: endValue)]
            if let rate = XIRR.rate(of: all) {
                let days = start.days(to: end)
                let cumulative = pow(1 + rate.doubleValue, Double(days) / 365) - 1
                moneyWeighted = ReturnFigure(cumulative: Decimal(approximating: cumulative) ?? rate, days: days)
            }
        }
        return InstrumentReturn(account: account, instrument: instrument, start: start, end: end,
                                startValue: startValue, endValue: endValue, netInvested: invested,
                                dividends: dividends, realizedGain: realized, gain: gain, moneyWeighted: moneyWeighted)
    }
}
