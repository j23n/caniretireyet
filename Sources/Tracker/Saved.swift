import Foundation
import Model

/// What the accounts in a scope saved over one stretch between two cuts,
/// check-ins or period ends (PROGRESS.md, "Saved"): the one count of money
/// saved that the savings rate, Trends' *Where your money came from*, the
/// saving pace and the Overview's bars add up or spread.
///
/// An account with a record before the stretch saved its new money over it
/// (``Valuator/change(from:to:in:)``). One whose records start in the
/// stretch held its first amount already: its first value without a flow
/// (`other`) and its new money. That amount counts as saved only as far as
/// money moved from the accounts tracked before it pays for it: above zero
/// (an asset) as far as their money taken out, below zero (a debt, such as
/// a loan paid out into the current account) as far as their money put in,
/// shared over the stretch's first amounts on that side in proportion to
/// them. The rest is what it ``startedWith``.
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
        for account in report.accounts {
            if let record = firstRecordDate(of: account.account), record > from, record <= through {
                firsts.append((account.account, account.change.other + account.change.newMoney))
            } else {
                saved[account.account] = account.change.newMoney
            }
        }
        // What the accounts tracked before put in and took out: the other side of a first amount moved from them.
        let putIn = saved.values.reduce(Decimal(0)) { $0 + max($1, 0) }
        let takenOut = saved.values.reduce(Decimal(0)) { $0 - min($1, 0) }
        let assets = firsts.reduce(Decimal(0)) { $0 + max($1.amount, 0) }
        let debts = firsts.reduce(Decimal(0)) { $0 - min($1.amount, 0) }
        var startedWith: [AccountID: Decimal] = [:]
        for first in firsts {
            let (offset, side) = first.amount > 0 ? (takenOut, assets) : (putIn, debts)
            let share: Decimal = side == 0 ? 0 : min(offset / side, 1)
            saved[first.account] = first.amount * share
            startedWith[first.account] = first.amount - first.amount * share
        }
        return SavedStretch(report: report, saved: saved, startedWith: startedWith)
    }
}
