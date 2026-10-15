import Foundation
import Model

/// What the accounts in a scope saved over one stretch between two cuts,
/// check-ins or period ends (PROGRESS.md, "Saved"): the one count of money
/// saved that the savings rate, Trends' *Where your money came from*, the
/// saving pace and the Overview's bars add up or spread.
///
/// An account with a record before the stretch saved what its change over
/// it counts as saved (``Valuator/change(from:to:in:)``). One whose records start in the
/// stretch held its first amount already: its first value without a saved amount
/// (`other`) and what it saved after it. That amount counts as saved only as far as
/// money moved from the accounts tracked before it pays for it, shared over
/// the stretch's first amounts on that side in proportion to them: above
/// zero (an asset) as far as their money taken out; below zero (a debt,
/// such as a loan paid out into the current account) as far as money moved
/// into their cash and savings accounts, added up, so a transfer between
/// two of them cancels out, and a broker's deposit or a mortgage's
/// principal, paid from the current account, doesn't offset it. The rest
/// is what it ``startedWith``.
public struct SavedStretch: Hashable, Sendable {
    /// How each account changed over the stretch, after `report.from` through `report.to`.
    public let report: ChangeReport
    /// What each account that counted in the stretch saved.
    public let saved: [AccountID: Decimal]
    /// What each account whose records start in the stretch held when they start.
    public let startedWith: [AccountID: Decimal]

    public init(report: ChangeReport, saved: [AccountID: Decimal], startedWith: [AccountID: Decimal]) {
        self.report = report
        self.saved = saved
        self.startedWith = startedWith
    }

    public var from: CalendarDate { report.from }
    public var to: CalendarDate { report.to }

    /// Everything the accounts saved over the stretch.
    public var total: Decimal {
        saved.keys.sorted().reduce(Decimal(0)) { $0 + (saved[$1] ?? 0) }
    }

    /// Everything the accounts whose records start in the stretch held then.
    public var totalStartedWith: Decimal {
        startedWith.keys.sorted().reduce(Decimal(0)) { $0 + (startedWith[$1] ?? 0) }
    }
}

extension Valuator {
    /// What the accounts in `scope` saved over each stretch between
    /// consecutive `cuts` (sorted dates, the first only where the first
    /// stretch starts), oldest first (``SavedStretch``).
    public func savedStretches(between cuts: [CalendarDate], in scope: NetWorthScope) -> [SavedStretch] {
        zip(cuts, cuts.dropFirst()).map { savedStretch(after: $0.0, through: $0.1, in: scope) }
    }

    /// The cuts of the stretches from `from` (exclusive) through `through`:
    /// every check-in of `scope` between them and `extra` dates between
    /// them, after `from` itself.
    public func savedCuts(after from: CalendarDate, through: CalendarDate, in scope: NetWorthScope,
                          adding extra: [CalendarDate] = []) -> [CalendarDate] {
        let inside = (checkInDates(in: scope, through: through) + extra + [through]).filter { $0 > from }
        return [from] + Set(inside).sorted()
    }

    /// What the accounts in `scope` saved after `from` through `through`
    /// (``SavedStretch``).
    func savedStretch(after from: CalendarDate, through: CalendarDate, in scope: NetWorthScope) -> SavedStretch {
        let report = change(from: from, to: through, in: scope)
        var saved: [AccountID: Decimal] = [:]
        var firsts: [(account: AccountID, amount: Decimal)] = []
        var takenOut: Decimal = 0
        var movedIn: Decimal = 0
        for account in report.accounts {
            if let record = firstRecordDate(of: account.account), record > from, record <= through {
                firsts.append((account.account, account.change.other + account.change.saved))
            } else {
                saved[account.account] = account.change.saved
                takenOut += max(-account.change.saved, 0)
                movedIn += moved(into: account, after: from, through: through) ?? 0
            }
        }
        let paidIn = max(movedIn, 0)
        let assets = firsts.reduce(Decimal(0)) { $0 + max($1.amount, 0) }
        let debts = firsts.reduce(Decimal(0)) { $0 - min($1.amount, 0) }
        var startedWith: [AccountID: Decimal] = [:]
        for first in firsts {
            let (offset, side) = first.amount > 0 ? (takenOut, assets) : (paidIn, debts)
            let share: Decimal = side == 0 ? 0 : min(offset / side, 1)
            saved[first.account] = first.amount * share
            startedWith[first.account] = first.amount - first.amount * share
        }
        return SavedStretch(report: report, saved: saved, startedWith: startedWith)
    }

    /// What moved into a cash or savings account from your other accounts
    /// after `from` through `through` (negative: out of it), in the base
    /// currency: the sum of its valuations' ``moved(_:previous:)``. Where
    /// one of them doesn't record money in and out, what it saved over
    /// those days, as nothing tells a transfer apart. `nil` for other kinds.
    private func moved(into change: AccountChange, after from: CalendarDate, through: CalendarDate) -> Decimal? {
        guard let account = accounts[change.account], account.kind.recordsMoneyInOut else { return nil }
        var total: Decimal = 0
        var previous: Valuation?
        for valuation in valuations(for: account.id) {
            defer { previous = valuation }
            guard valuation.date > from, valuation.date <= through else { continue }
            guard let moved = self.moved(valuation, previous: previous),
                  let inBase = fx.convert(moved, from: account.currency, to: baseCurrency, on: valuation.date)
            else { return change.change.saved }
            total += inBase
        }
        return total
    }
}
