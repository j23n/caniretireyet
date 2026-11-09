import Foundation
import Model

/// How much of the money that came in was saved over a period (PROGRESS.md,
/// "Savings rate"). What was saved is worked out from balances and trades:
/// what every account in net worth saved, as the Overview's *This
/// year* splits it, so money moved between your accounts cancels out, a
/// refund lowers what was spent and a loan's principal repaid is saved. What
/// came in is the money in that cash and savings accounts record, plus what
/// was paid into pension funds and TFR, pay that never reaches a cash
/// account, less tax: the tax money out recorded, in the days it was
/// paid, and what moved into tax pots, so it's after tax.
/// A one-off, such as an inheritance, is saved but neither came in nor
/// spent: the rate is what the pay saved (``savedFromPay``) over what came
/// in, and what was spent is the rest of the pay. Only accounts in net
/// worth count, on both sides. In the base currency.
public struct SavingsRate: Hashable, Sendable {
    /// The money in it's worked out from: the values dated in the period.
    public var moneyInOut: MoneyInOutSummary
    /// Where the days the pay covers start (exclusive): the valuation the
    /// values of the pay account are measured from
    /// (``Valuator/savingsRate(from:through:)``). What was saved, the
    /// pension contributions and the tax set aside are counted over the
    /// days after it through ``payThrough``.
    public var from: CalendarDate
    /// The period's last day.
    public var through: CalendarDate
    /// Where the days the pay covers end, at most ``through``: the date of
    /// the latest value counted of the pay account. When
    /// that account's value runs across the period's end, ``from``: the pay
    /// covers no days.
    public var payThrough: CalendarDate
    /// What was saved into pension funds and TFR over the days the pay
    /// covers, each account's at least zero: money taken out of them isn't
    /// income.
    public var pensionContributions: Decimal
    /// What moved into tax pots outside net worth over those days
    /// (``Valuator/taxSetAside(after:through:)``): tax, so neither came in
    /// nor spent.
    public var taxSetAside: Decimal
    /// What each account in net worth saved over those days
    /// (``Valuator/saved(after:through:)``): what it saved, less what a new
    /// account's first value already held.
    public var savedByAccount: [AccountID: Decimal]
    /// The accounts in net worth that a plan leaves out
    /// (``Model/Account/includedInPlan``), such as a home and its mortgage.
    public var accountsOutsidePlan: Set<AccountID>
    /// Whether every price and exchange rate needed for what was saved was known.
    public var isPriced: Bool

    /// - Parameter payThrough: where the days the pay covers end; without
    ///   it, the latest value counted (``MoneyInOutSummary/lastCounted``),
    ///   else `through`.
    public init(moneyInOut: MoneyInOutSummary, from: CalendarDate, through: CalendarDate,
                payThrough: CalendarDate? = nil,
                pensionContributions: Decimal = 0, taxSetAside: Decimal = 0,
                savedByAccount: [AccountID: Decimal] = [:],
                accountsOutsidePlan: Set<AccountID> = [],
                isPriced: Bool = true) {
        self.moneyInOut = moneyInOut
        self.from = from
        self.through = through
        self.payThrough = min(payThrough ?? moneyInOut.lastCounted ?? through, through)
        self.pensionContributions = pensionContributions
        self.taxSetAside = taxSetAside
        self.savedByAccount = savedByAccount
        self.accountsOutsidePlan = accountsOutsidePlan
        self.isPriced = isPriced
    }

    /// The account kinds whose saved amount counts as pay that was saved.
    public static let pensionKinds: Set<AccountKind> = [.pensionFund, .tfr]

    /// Tax: the tax money out recorded with the values counted, less
    /// refunds (``MoneyInOutSummary/taxes``), in the days it was paid, plus
    /// what moved into tax pots (``taxSetAside``). Neither came in nor
    /// spent.
    public var tax: Decimal { moneyInOut.taxes + taxSetAside }

    /// What came in, after tax: money in, plus the pension contributions,
    /// less the tax.
    public var income: Decimal { moneyInOut.moneyIn + pensionContributions - tax }

    /// What was saved: what every account saved over the days, added up,
    /// the one-offs (``oneOffs``) with it. A tax bill paid in the days is
    /// out of it.
    public var saved: Decimal {
        savedByAccount.keys.sorted().reduce(Decimal(0)) { $0 + (savedByAccount[$1] ?? 0) }
    }

    /// What the accounts a plan leaves out saved of ``saved``
    /// (``accountsOutsidePlan``), such as a mortgage's principal repaid. A
    /// plan counts none of it as saved: its spending pays for it.
    public var savedOutsidePlan: Decimal {
        accountsOutsidePlan.sorted().reduce(Decimal(0)) { $0 + (savedByAccount[$1] ?? 0) }
    }

    /// What the accounts a plan counts saved: ``saved`` less
    /// ``savedOutsidePlan``. What a plan's planned saving compares with.
    public var savedInPlan: Decimal { saved - savedOutsidePlan }

    /// Money from outside that was neither income nor spending, such as an
    /// inheritance (``MoneyInOutSummary/oneOffs``): in what was saved, but
    /// not in what came in or what was spent.
    public var oneOffs: Decimal { moneyInOut.oneOffs }

    /// What the pay saved: what was saved, less the one-offs. What the
    /// rate counts: what came in, less what was spent.
    public var savedFromPay: Decimal { saved - oneOffs }

    /// What was spent: what came in less what the pay saved
    /// (``savedFromPay``). Below zero when more was saved than came in,
    /// usually because some income wasn't recorded.
    public var spent: Decimal { income - savedFromPay }

    /// What came in, the tax, what was spent, the one-offs and what was
    /// saved, as Today's *Your pay* splits them (``WhatMoved/Pay``), over
    /// the days after ``from`` through ``payThrough``: its
    /// ``WhatMoved/Pay/spent`` is ``spent``, its ``WhatMoved/Pay/saved`` is
    /// ``saved`` and its ``WhatMoved/Pay/savedShare`` is ``rate``.
    public var pay: WhatMoved.Pay {
        WhatMoved.Pay(moneyIn: moneyInOut.moneyIn, pension: pensionContributions, tax: tax, saved: saved,
                      oneOffs: oneOffs, from: from, through: payThrough)
    }

    /// ``spent`` scaled to a year by the days the pay covers, at least one,
    /// rounded to cents: from ``from`` to ``payThrough``, so the days after
    /// the pay's latest value, which record nothing yet, don't make it
    /// smaller. When the pay covers no days, by the days of the values
    /// counted instead (``MoneyInOutSummary/measuredFrom`` to
    /// ``MoneyInOutSummary/lastCounted``), so what came in to another
    /// account isn't scaled as if spent in a day.
    public var spentPerYear: Decimal { perYear(spent) }

    /// What was spent as a plan counts it: ``spent`` plus what was saved
    /// into the accounts it leaves out (``savedOutsidePlan``), which leaves
    /// the plan's accounts as spending does. What a plan's spending
    /// compares with.
    public var spentInPlan: Decimal { spent + savedOutsidePlan }

    /// ``spentInPlan`` scaled to a year, as ``spentPerYear``.
    public var spentInPlanPerYear: Decimal { perYear(spentInPlan) }

    /// `amount` over the days the pay covers scaled to a year, rounded to
    /// cents (``spentPerYear``).
    private func perYear(_ amount: Decimal) -> Decimal {
        var days = from.days(to: payThrough)
        if days == 0, let start = moneyInOut.measuredFrom, let end = moneyInOut.lastCounted {
            days = start.days(to: end)
        }
        return (amount * 365 / Decimal(max(1, days))).rounded(scale: 2)
    }

    /// ``savedFromPay`` over ``income``; negative when more was spent than
    /// came in. `nil` when nothing came in after tax (``noRate`` says why).
    public var rate: Decimal? {
        income > 0 ? savedFromPay / income : nil
    }

    /// Why there's no ``rate``: what came in after tax isn't above zero.
    public enum NoRate: Hashable, Sendable {
        /// Nothing came in, and no tax.
        case nothingCameIn
        /// Money in and the pension contributions add up to less than zero.
        case lessThanNothingCameIn
        /// Tax took as much as came in, or more.
        case moreTaxThanCameIn
    }

    /// Why there's no ``rate``; `nil` when there's one.
    public var noRate: NoRate? {
        guard income <= 0 else { return nil }
        let beforeTax = moneyInOut.moneyIn + pensionContributions
        if beforeTax < 0 { return .lessThanNothingCameIn }
        if tax > 0 { return .moreTaxThanCameIn }
        return .nothingCameIn
    }
}

extension Valuator {
    /// The savings rate over the money in recorded by valuations dated from
    /// `from` through `through` (``moneyInOut(from:through:accounts:)``) of
    /// the accounts in net worth,
    /// with what was saved (``saved(after:through:)``), what was saved
    /// into pension funds and TFR (``SavingsRate/pensionKinds``) and the tax
    /// set aside over the days the pay covers (``payDays(from:through:)``):
    /// those of the pay account. So an account checked
    /// rarely, or recording money in for longer, doesn't stretch them, and
    /// while that account stays the same, the days of consecutive periods
    /// meet: nothing saved counts in both, and nothing falls between them.
    /// When nothing came in, the days are those of the values counted.
    /// `nil` when no money in and out was counted.
    public func savingsRate(from: CalendarDate, through: CalendarDate) -> SavingsRate? {
        savingsRate(from: from, through: through, payAfter: nil, notBefore: nil)
    }

    /// ``savingsRate(from:through:)``, with the pay's days starting after
    /// `payAfter` instead, when there is one, or otherwise after
    /// `notBefore` at the earliest, and ending no earlier: so a series of
    /// periods whose days each start where the one before's end
    /// (``SavingsRate/payThrough``), or after a period with nothing
    /// counted no earlier than where the latest that counted anything
    /// ended, covers every day at most once, even when the pay account
    /// changes between them (``moneyInOutSeries(_:through:)``).
    func savingsRate(from: CalendarDate, through: CalendarDate, payAfter: CalendarDate?,
                     notBefore: CalendarDate?) -> SavingsRate? {
        let money = moneyInOut(from: from, through: through, accounts: cameInAccounts)
        guard let measuredFrom = money.measuredFrom else { return nil }
        var days = payDays(from: from, through: through) ?? (measuredFrom, money.lastCounted ?? through)
        if let start = payAfter ?? notBefore.flatMap({ $0 > days.after ? $0 : nil }) {
            days = (start, max(days.through, start))
        }
        let saved = saved(after: days.after, through: days.through)
        let contributions = saved.byAccount.keys.sorted().reduce(Decimal(0)) { total, id in
            guard let account = accounts[id], SavingsRate.pensionKinds.contains(account.kind) else { return total }
            return total + max(saved.byAccount[id] ?? 0, 0)
        }
        let tax = taxSetAside(after: days.after, through: days.through)
        let outsidePlan = saved.byAccount.keys.filter { accounts[$0]?.includedInPlan == false }
        return SavingsRate(moneyInOut: money, from: days.after, through: through, payThrough: days.through,
                           pensionContributions: contributions,
                           taxSetAside: tax.amount,
                           savedByAccount: saved.byAccount,
                           accountsOutsidePlan: Set(outsidePlan),
                           isPriced: saved.isPriced && tax.isPriced)
    }

    /// The days the pay of the values dated from `from` through `through`
    /// covers (PROGRESS.md, "Savings rate"), those of the pay account: of
    /// the cash and savings accounts in net worth, the one the most came
    /// into in the period's days, in the base currency, over its values
    /// counted that are dated in the period, or, for an account without
    /// one, over its value counted that runs across the period's end
    /// (dated after it, measured from a value before it); the first by ID
    /// on a tie. What came into an account is spread evenly over the days
    /// its values cover, and only the part in the period's days counts, so
    /// an account valued every quarter doesn't outweigh one valued every
    /// month by its quarter's money in. The days are after the valuation
    /// its values counted in the period are measured from through the
    /// latest of them. When its value runs across the end instead, its
    /// check-in was skipped: the period has no days of pay, and they count
    /// with the period that value is dated in. `nil` when nothing came in.
    private func payDays(from: CalendarDate, through: CalendarDate)
        -> (after: CalendarDate, through: CalendarDate)? {
        /// The part of `amount`, spread evenly over the days after `start`
        /// through `end`, that falls in the period.
        func inPeriod(_ amount: Decimal, after start: CalendarDate, through end: CalendarDate) -> Decimal {
            let days = start.days(to: end)
            guard days > 0 else { return amount }
            let inside = max(start, from.adding(days: -1)).days(to: min(end, through))
            return amount * Decimal(max(inside, 0)) / Decimal(days)
        }
        var best: (moneyIn: Decimal, days: (after: CalendarDate, through: CalendarDate))?
        for id in cameInAccounts.sorted() {
            let own = moneyInOut(from: from, through: through, accounts: [id])
            var pay: (moneyIn: Decimal, days: (after: CalendarDate, through: CalendarDate))?
            if let after = own.measuredFrom, let last = own.lastCounted {
                pay = (inPeriod(own.moneyIn, after: after, through: last), (after, last))
            } else if let across = valueAcross(through, of: id) {
                pay = (inPeriod(across.moneyIn, after: across.previous, through: across.date),
                       (across.previous, across.previous))
            }
            if let pay, pay.moneyIn > (best?.moneyIn ?? 0) { best = pay }
        }
        return best?.days
    }

    /// A cash or savings account's value counted that runs across `day`:
    /// its first value dated after it, when it's measured from a value
    /// before it, with the date it's measured from, its own date and its
    /// money in, in the base currency. `nil` when the account has a value
    /// on the day, none after it, or the one after it isn't counted.
    private func valueAcross(_ day: CalendarDate, of id: AccountID)
        -> (previous: CalendarDate, date: CalendarDate, moneyIn: Decimal)? {
        guard let account = accounts[id] else { return nil }
        let values = valuations(for: id)
        guard let index = values.firstIndex(where: { $0.date > day }), index > 0,
              values[index - 1].date < day,
              let counted = values[index].moneyInOut(on: account.kind).counted,
              let moneyIn = fx.convert(counted.moneyIn, from: account.currency, to: baseCurrency,
                                       on: values[index].date)
        else { return nil }
        return (values[index - 1].date, values[index].date, moneyIn)
    }

    /// What moved into tax pots outside net worth (``Model/AccountKind/taxPot``)
    /// from your other accounts by their values dated after `from` through
    /// `through`, in the base currency at each value's date: each value's
    /// ``moved(_:previous:)``, put in less taken back, so the tax paid
    /// from a pot (its money out) and refunds into it (its money in)
    /// change nothing. A value without both amounts counts what it saved,
    /// the whole change, when it's above zero: a drop is taken as tax paid. A
    /// pot's first value is what it held when its records start, not money
    /// put in. A tax pot in net worth counts as savings instead: what's put
    /// in is saved.
    public func taxSetAside(after from: CalendarDate, through: CalendarDate) -> (amount: Decimal, isPriced: Bool) {
        var total: Decimal = 0
        var isPriced = true
        var problems: [ValuationProblem] = []
        for account in accounts.values.sorted(by: { $0.id < $1.id })
        where account.kind == .taxPot && !account.includedInNetWorth {
            var previous: Valuation?
            for valuation in valuations(for: account.id) {
                defer { previous = valuation }
                guard let previous, valuation.date > from, valuation.date <= through else { continue }
                let moved = self.moved(valuation, previous: previous)
                    ?? saved(valuation, previous: previous).map { max($0, 0) }
                guard let moved,
                      let amount = converted(moved, from: account.currency, to: baseCurrency, on: valuation.date,
                                             for: account.id, problems: &problems)
                else {
                    isPriced = false
                    continue
                }
                total += amount
            }
        }
        return (total, isPriced)
    }

    /// The accounts whose money in counts as came in: the cash and savings
    /// accounts in net worth.
    public var cameInAccounts: Set<AccountID> {
        Set(accounts.values.filter { $0.kind.recordsMoneyInOut && $0.includedInNetWorth }.map(\.id))
    }

    /// `report`'s split of net worth's change with what it saved as
    /// ``WhatMoved/saved`` counts it (``saved(after:through:)`` over its
    /// days), the one-offs (``MoneyInOutSummary/oneOffs``) with it: the part
    /// of new accounts' first values counted as what they already held moves
    /// to other. A tax bill paid in the days is out of saved then, as the
    /// savings rate counts it. For the Overview's bars and the check-in's.
    public func savedSplit(of report: ChangeReport) -> ValueChange {
        var change = report.total
        let saved = saved(after: report.from, through: report.to).byAccount.values.reduce(Decimal(0), +)
        change.other += change.saved - saved
        change.saved = saved
        return change
    }

    /// ``savingsRate(from:through:)`` over the twelve months that end on `date`.
    public func savingsRate(overYearEndingOn date: CalendarDate) -> SavingsRate? {
        savingsRate(from: date.adding(years: -1).adding(days: 1), through: date)
    }

    /// What each account in net worth saved after `from` through `through`
    /// (PROGRESS.md, "Savings rate"): its saved amount over each stretch
    /// between check-ins (``SavedStretch``), added up, so a new account's
    /// first value counts only as far as money moved from the accounts
    /// tracked before it pays for it.
    public func saved(after from: CalendarDate, through: CalendarDate)
        -> (byAccount: [AccountID: Decimal], isPriced: Bool) {
        var byAccount: [AccountID: Decimal] = [:]
        var isPriced = true
        for stretch in savedStretches(between: savedCuts(after: from, through: through, in: .netWorth),
                                      in: .netWorth) {
            byAccount.merge(stretch.saved, uniquingKeysWith: +)
            isPriced = isPriced && stretch.report.isPriced
        }
        return (byAccount, isPriced)
    }
}
