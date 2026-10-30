import Foundation
import Model

/// How net worth changed between two check-ins, every part of it counted
/// (UI.md, "What moved it"): your pay, what came in less the tax and what
/// was spent, which leaves what you saved; and net worth's change, what you
/// saved plus what markets did and the rest. The parts add up exactly:
/// `saved + markets + oneOffs + startedWith + lost + unexplained == change`,
/// and with pay, `pay.cameIn - pay.tax - pay.spent == saved`.
///
/// As in the savings rate (``SavingsRate``), tax counts when it's paid: a
/// bill paid from a cash or savings account in the days is tax of those
/// days, so the parts add up to what net worth did. What moved into a tax
/// pot outside net worth is tax too.
/// In the base currency.
public struct WhatMoved: Hashable, Sendable {
    public let from: CalendarDate
    public let to: CalendarDate
    /// Net worth on `from`.
    public let start: Decimal
    /// Net worth's change.
    public let change: Decimal
    /// What every account in net worth saved (``Valuator/saved(after:through:)``),
    /// less the one-offs.
    public let saved: Decimal
    /// Price and FX movement, interest, reinvested dividends.
    public let markets: Decimal
    /// Money from outside that was neither income nor spending, such as an
    /// inheritance (``MoneyInOutSummary/oneOffs``).
    public let oneOffs: Decimal
    /// What accounts whose records start in the days held then, as far as
    /// nothing tracked before paid for it (``SavedStretch/startedWith``).
    public let startedWith: Decimal
    /// What belongings with a depreciation are estimated to have lost
    /// (``ValueChange/lost``).
    public let lost: Decimal
    /// Your pay; `nil` when no cash or savings account in net worth records
    /// money in and out in the days.
    public let pay: Pay?
    /// Whether every price and exchange rate needed was known.
    public let isPriced: Bool

    /// What came in, the tax and what was spent, which leave ``saved``.
    public struct Pay: Hashable, Sendable {
        /// The money in that cash and savings accounts in net worth recorded.
        public let moneyIn: Decimal
        /// What was saved into pension funds and TFR, each account's at
        /// least zero: pay that never reaches a cash account.
        public let pension: Decimal
        /// The tax recorded with the values of cash and savings accounts in
        /// net worth (``Model/Valuation/tax``), less refunds, and what
        /// moved into tax pots outside net worth.
        public let tax: Decimal
        /// What was saved: ``WhatMoved/saved``.
        public let saved: Decimal

        public init(moneyIn: Decimal, pension: Decimal, tax: Decimal, saved: Decimal) {
            self.moneyIn = moneyIn
            self.pension = pension
            self.tax = tax
            self.saved = saved
        }

        /// Money in and the pension contributions, before tax.
        public var cameIn: Decimal { moneyIn + pension }

        /// What came in, less the tax.
        public var afterTax: Decimal { cameIn - tax }

        /// What was spent: what came in after tax, less what was saved.
        /// Below zero when more was saved than came in, usually because some
        /// income wasn't recorded.
        public var spent: Decimal { afterTax - saved }

        /// What was saved of what came in after tax, e.g. 0.39; `nil` when
        /// nothing came in after tax.
        public var savedShare: Decimal? {
            afterTax > 0 ? saved / afterTax : nil
        }
    }

    public init(from: CalendarDate, to: CalendarDate, start: Decimal, change: Decimal, saved: Decimal,
                markets: Decimal, oneOffs: Decimal = 0, startedWith: Decimal = 0, lost: Decimal = 0,
                pay: Pay? = nil, isPriced: Bool = true) {
        self.from = from
        self.to = to
        self.start = start
        self.change = change
        self.saved = saved
        self.markets = markets
        self.oneOffs = oneOffs
        self.startedWith = startedWith
        self.lost = lost
        self.pay = pay
        self.isPriced = isPriced
    }

    /// The rest of the change: a balance whose saved amount isn't known,
    /// or needs a missing price or exchange rate.
    public var unexplained: Decimal {
        change - saved - markets - oneOffs - startedWith - lost
    }

    /// Everything but what was saved and markets.
    public var other: Decimal { oneOffs + startedWith + lost + unexplained }
}

extension Valuator {
    /// What moved net worth between the dates of `report`, a change of net
    /// worth (``WhatMoved``).
    public func whatMoved(_ report: ChangeReport) -> WhatMoved {
        let stretches = savedStretches(between: savedCuts(after: report.from, through: report.to, in: .netWorth),
                                       in: .netWorth)
        var byAccount: [AccountID: Decimal] = [:]
        var startedWith: Decimal = 0
        var isPriced = report.isPriced
        for stretch in stretches {
            byAccount.merge(stretch.saved, uniquingKeysWith: +)
            startedWith += stretch.totalStartedWith
            isPriced = isPriced && stretch.report.isPriced
        }
        let money = moneyInOut(from: report.from.adding(days: 1), through: report.to, accounts: cameInAccounts)
        // A value without an exchange rate is left out of money in and the tax.
        isPriced = isPriced && money.unconverted.isEmpty
        let saved = byAccount.keys.sorted().reduce(Decimal(0)) { $0 + (byAccount[$1] ?? 0) } - money.oneOffs
        var pay: WhatMoved.Pay?
        if !money.isEmpty {
            let pension = byAccount.keys.sorted().reduce(Decimal(0)) { total, id in
                guard let account = accounts[id], SavingsRate.pensionKinds.contains(account.kind) else { return total }
                return total + max(byAccount[id] ?? 0, 0)
            }
            let setAside = taxSetAside(after: report.from, through: report.to)
            isPriced = isPriced && setAside.isPriced
            pay = WhatMoved.Pay(moneyIn: money.moneyIn, pension: pension, tax: money.taxes + setAside.amount,
                                saved: saved)
        }
        return WhatMoved(from: report.from, to: report.to, start: report.total.start, change: report.total.change,
                         saved: saved, markets: report.total.market, oneOffs: money.oneOffs,
                         startedWith: startedWith, lost: report.total.lost, pay: pay, isPriced: isPriced)
    }
}
