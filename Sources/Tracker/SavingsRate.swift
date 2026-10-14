import Foundation
import Model

/// How much of the money that came in was saved over a period (PROGRESS.md,
/// "Savings rate"). What was saved is worked out from balances and trades:
/// what every account in net worth saved, as the Overview's *This
/// year* splits it, so money moved between your accounts cancels out, a
/// refund lowers what was spent and a loan's principal repaid is saved. What
/// came in is the money in that cash and savings accounts record, plus what
/// was paid into pension funds and TFR, pay that never reaches a cash
/// account, less tax: the tax money out recorded and what moved into tax
/// pots, so it's after tax. What was spent is the rest. Only accounts in net worth count, on both sides. In
/// the base currency.
public struct SavingsRate: Hashable, Sendable {
    /// The money in it's worked out from.
    public var moneyInOut: MoneyInOutSummary
    /// The days counted, the days the pay that came in covers: from the
    /// valuation the counted values of the account the most came into are
    /// measured from (exclusive) through ``through``.
    public var from: CalendarDate
    public var through: CalendarDate
    /// What was saved into pension funds and TFR over those days, each account's
    /// at least zero: money taken out of them isn't income.
    public var pensionContributions: Decimal
    /// What moved into tax pots outside net worth over those days
    /// (``Valuator/taxSetAside(after:through:)``): tax, so neither came in
    /// nor spent.
    public var taxSetAside: Decimal
    /// What each account in net worth saved over those days
    /// (``Valuator/saved(after:through:)``): what it saved, less what a new
    /// account's first value already held.
    public var savedByAccount: [AccountID: Decimal]
    /// Whether every price and exchange rate needed for what was saved was known.
    public var isPriced: Bool

    public init(moneyInOut: MoneyInOutSummary, from: CalendarDate, through: CalendarDate,
                pensionContributions: Decimal = 0, taxSetAside: Decimal = 0,
                savedByAccount: [AccountID: Decimal] = [:],
                isPriced: Bool = true) {
        self.moneyInOut = moneyInOut
        self.from = from
        self.through = through
        self.pensionContributions = pensionContributions
        self.taxSetAside = taxSetAside
        self.savedByAccount = savedByAccount
        self.isPriced = isPriced
    }

    /// The account kinds whose saved amount counts as pay that was saved.
    public static let pensionKinds: Set<AccountKind> = [.pensionFund, .tfr]

    /// Tax: the tax money out of the values counted recorded
    /// (``MoneyInOutSummary/taxes``, less refunds), plus what moved into tax
    /// pots (``taxSetAside``). Neither came in nor spent.
    public var tax: Decimal { moneyInOut.taxes + taxSetAside }

    /// What came in, after tax: money in, plus the pension contributions,
    /// less the tax.
    public var income: Decimal { moneyInOut.moneyIn + pensionContributions - tax }

    /// What was saved: what every account saved over the days, added up,
    /// less the one-offs (``MoneyInOutSummary/oneOffs``), which are neither
    /// came in nor spent.
    public var saved: Decimal {
        savedByAccount.keys.sorted().reduce(Decimal(0)) { $0 + (savedByAccount[$1] ?? 0) } - oneOffs
    }

    /// Money from outside that was neither income nor spending, such as an
    /// inheritance: left out of what was saved.
    public var oneOffs: Decimal { moneyInOut.oneOffs }

    /// What was spent: what came in less what was saved. Below zero when
    /// more was saved than came in, usually because some income wasn't
    /// recorded.
    public var spent: Decimal { income - saved }

    /// ``spent`` scaled to a year by the days counted, rounded to cents.
    public var spentPerYear: Decimal {
        (spent * 365 / Decimal(max(1, from.days(to: through)))).rounded(scale: 2)
    }

    /// ``saved`` over ``income``; negative when more was spent than came in.
    /// `nil` when nothing came in.
    public var rate: Decimal? {
        income > 0 ? saved / income : nil
    }
}

extension Valuator {
    /// The savings rate over the money in recorded by valuations dated from
    /// `from` through `through` (``moneyInOut(from:through:accounts:)``) of
    /// the accounts in net worth,
    /// with what was saved (``saved(after:through:)``) and what was saved
    /// into pension funds and TFR (``SavingsRate/pensionKinds``) over the
    /// days the pay covers: those of the account the most came into, so an
    /// account checked rarely, or recording money in for longer, doesn't
    /// stretch them. `nil` when no money in and out was counted.
    public func savingsRate(from: CalendarDate, through: CalendarDate) -> SavingsRate? {
        let counted = cameInAccounts
        let cash = accounts.values.filter { counted.contains($0.id) }
        let money = moneyInOut(from: from, through: through, accounts: counted)
        guard let measuredFrom = money.measuredFrom else { return nil }
        let pay = cash.sorted { $0.id < $1.id }
            .map { moneyInOut(from: from, through: through, accounts: [$0.id]) }
            .filter { $0.moneyIn > 0 }
            .max { $0.moneyIn < $1.moneyIn }
        let start = pay?.measuredFrom ?? measuredFrom
        let saved = saved(after: start, through: through)
        let contributions = saved.byAccount.keys.sorted().reduce(Decimal(0)) { total, id in
            guard let account = accounts[id], SavingsRate.pensionKinds.contains(account.kind) else { return total }
            return total + max(saved.byAccount[id] ?? 0, 0)
        }
        let tax = taxSetAside(after: start, through: through)
        return SavingsRate(moneyInOut: money, from: start, through: through, pensionContributions: contributions,
                           taxSetAside: tax.amount, savedByAccount: saved.byAccount,
                           isPriced: saved.isPriced && tax.isPriced)
    }

    /// What moved into tax pots outside net worth (``Model/AccountKind/taxPot``)
    /// from your other accounts by their values dated after `from` through
    /// `through`, in the base currency at each value's date: each value's
    /// ``moved(_:previous:)``, put in less taken back, so the tax paid
    /// from a pot (its money out) and refunds into it (its money in)
    /// change nothing. A value without both amounts counts its flow, the
    /// whole change, when it's above zero: a drop is taken as tax paid. A
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
                    ?? flow(of: valuation, previous: previous).map { max($0, 0) }
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

    /// `report`'s split of net worth's change with what it saved as the
    /// savings rate counts what was saved (``saved(after:through:)``) over
    /// its days: the part of new accounts' first values counted as what
    /// they already held, and the one-offs (``MoneyInOutSummary/oneOffs``),
    /// move to other. For the Overview's bars.
    public func savedSplit(of report: ChangeReport) -> ValueChange {
        var change = report.total
        let oneOffs = moneyInOut(from: report.from.adding(days: 1), through: report.to,
                                 accounts: cameInAccounts).oneOffs
        let saved = saved(after: report.from, through: report.to).byAccount.values.reduce(Decimal(0), +) - oneOffs
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
