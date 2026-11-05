import Foundation
import Model

/// How net worth changed between two check-ins, every part of it counted
/// (UI.md, "What moved it"): net worth's change, what you saved plus what
/// markets did and the rest; and your pay, what came in less the tax and
/// what was spent, which leaves what the pay saved, then the one-offs,
/// which leave what was saved. A one-off, such as an inheritance, is saved
/// but neither came in nor spent. The parts add up exactly: `saved +
/// markets + startedWith + lost + unexplained == change`, and with pay,
/// `pay.cameIn - pay.tax - pay.spent == pay.savedFromPay` and
/// `pay.savedFromPay + pay.oneOffs == pay.saved`.
///
/// Net worth's change is split over the check-in's own days. The pay is
/// the savings rate over the check-in's values (``SavingsRate/pay``),
/// which covers the days of the account the most came into (``Pay/from``,
/// ``Pay/through``): when that account has no value on the check-in
/// before, such as a purchase's or another account's check-in in the
/// middle of its month, they start earlier, and ``Pay/saved`` is what was
/// saved over them, not ``saved``.
///
/// As in the savings rate, tax counts when it's paid: a bill paid from a
/// cash or savings account in the days is tax of those days. What moved
/// into a tax pot outside net worth is tax too.
/// In the base currency.
public struct WhatMoved: Hashable, Sendable {
    public let from: CalendarDate
    public let to: CalendarDate
    /// Net worth on `from`.
    public let start: Decimal
    /// Net worth's change.
    public let change: Decimal
    /// What every account in net worth saved (``Valuator/saved(after:through:)``),
    /// the one-offs with it (``Pay/oneOffs``).
    public let saved: Decimal
    /// Price and FX movement, interest, reinvested dividends.
    public let markets: Decimal
    /// What accounts whose records start in the days held then, as far as
    /// nothing tracked before paid for it (``SavedStretch/startedWith``).
    public let startedWith: Decimal
    /// What belongings with a depreciation are estimated to have lost
    /// (``ValueChange/lost``).
    public let lost: Decimal
    /// Your pay, the savings rate over the check-in's values; `nil` when no
    /// cash or savings account in net worth records money in and out in the
    /// days.
    public let pay: Pay?
    /// Whether every price and exchange rate needed was known.
    public let isPriced: Bool

    /// What came in, the tax and what was spent, which leave what the pay
    /// saved over the days it covers, then the one-offs, which leave what
    /// was saved.
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
        /// What every account in net worth saved over the days the pay
        /// covers, the one-offs with it (``SavingsRate/saved``):
        /// ``WhatMoved/saved`` when they're the check-in's days.
        public let saved: Decimal
        /// Money from outside that was neither income nor spending, such as
        /// an inheritance (``SavingsRate/oneOffs``): in ``saved``, but not
        /// in what came in or what was spent.
        public let oneOffs: Decimal
        /// Where the days the pay covers start (exclusive) and end
        /// (``SavingsRate/from``, ``SavingsRate/payThrough``); `nil` for a
        /// pay made from amounts alone.
        public let from: CalendarDate?
        public let through: CalendarDate?

        public init(moneyIn: Decimal, pension: Decimal, tax: Decimal, saved: Decimal, oneOffs: Decimal = 0,
                    from: CalendarDate? = nil, through: CalendarDate? = nil) {
            self.moneyIn = moneyIn
            self.pension = pension
            self.tax = tax
            self.saved = saved
            self.oneOffs = oneOffs
            self.from = from
            self.through = through
        }

        /// Money in and the pension contributions, before tax.
        public var cameIn: Decimal { moneyIn + pension }

        /// What came in, less the tax.
        public var afterTax: Decimal { cameIn - tax }

        /// What the pay saved: what was saved, less the one-offs
        /// (``SavingsRate/savedFromPay``).
        public var savedFromPay: Decimal { saved - oneOffs }

        /// What was spent: what came in after tax, less what the pay saved.
        /// Below zero when more was saved than came in, usually because some
        /// income wasn't recorded.
        public var spent: Decimal { afterTax - savedFromPay }

        /// What the pay saved of what came in after tax, e.g. 0.39: the
        /// savings rate. `nil` when nothing came in after tax.
        public var savedShare: Decimal? {
            afterTax > 0 ? savedFromPay / afterTax : nil
        }
    }

    public init(from: CalendarDate, to: CalendarDate, start: Decimal, change: Decimal, saved: Decimal,
                markets: Decimal, startedWith: Decimal = 0, lost: Decimal = 0,
                pay: Pay? = nil, isPriced: Bool = true) {
        self.from = from
        self.to = to
        self.start = start
        self.change = change
        self.saved = saved
        self.markets = markets
        self.startedWith = startedWith
        self.lost = lost
        self.pay = pay
        self.isPriced = isPriced
    }

    /// The rest of the change: a balance whose saved amount isn't known,
    /// or needs a missing price or exchange rate.
    public var unexplained: Decimal {
        change - saved - markets - startedWith - lost
    }

    /// Everything but what was saved and markets.
    public var other: Decimal { startedWith + lost + unexplained }
}

extension Valuator {
    /// What moved net worth between the dates of `report`, a change of net
    /// worth (``WhatMoved``), with the pay of the values dated in its days
    /// (``savingsRate(from:through:)``).
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
        let saved = byAccount.keys.sorted().reduce(Decimal(0)) { $0 + (byAccount[$1] ?? 0) }
        let rate = money.isEmpty ? nil : savingsRate(from: report.from.adding(days: 1), through: report.to)
        isPriced = isPriced && (rate?.isPriced ?? true)
        return WhatMoved(from: report.from, to: report.to, start: report.total.start, change: report.total.change,
                         saved: saved, markets: report.total.market,
                         startedWith: startedWith, lost: report.total.lost, pay: rate?.pay, isPriced: isPriced)
    }
}
