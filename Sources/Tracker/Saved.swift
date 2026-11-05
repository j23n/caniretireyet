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
/// zero (an asset) as far as money moved out of their cash and savings
/// accounts that record money in and out, and what property or belongings
/// they sold (worth nothing at the stretch's end) were worth, as the price
/// landed in a cash account, added up, less what their other assets saved,
/// as that money may have landed there (pension funds, which pay fills,
/// and debts, whose payments are money out, aside), and the money taken
/// out of their other accounts that hold money: not a debt's growth, which
/// is spent or lands where it's paid out, nor the drop of property or
/// belongings still held, which is lost value; below zero (a debt, such
/// as a loan paid out into the current account) as far as money moved
/// into their cash and savings accounts, added up. So a transfer between two of them cancels
/// out, a broker funded from a current account that also had pay come in
/// is paid for, and a broker's deposit or a mortgage's principal, paid
/// from the current account, doesn't offset a debt. The rest is what it
/// ``startedWith``.
///
/// A cash or savings account's value covers the days since its value
/// before, which can start before the stretch when another account's
/// value made a check-in in between. What it says moved then also pays,
/// with the first amounts, for what accounts whose records start in those
/// days still started with: the part it pays is saved in this stretch,
/// and comes off what they started with.
public struct SavedStretch: Hashable, Sendable {
    /// How each account changed over the stretch, after `report.from` through `report.to`.
    public let report: ChangeReport
    /// What each account that counted in the stretch saved.
    public let saved: [AccountID: Decimal]
    /// What each account whose records start in the stretch held when they
    /// start; and what money moved in the stretch paid for of what an
    /// account that started in days before it still started with, below zero.
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

    /// Everything the accounts whose records start in the stretch held
    /// then, less what money moved in it paid for of what accounts that
    /// started before it still started with (``startedWith``).
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
        // The amounts money moved may pay for: the first amounts of the accounts whose records
        // start in the stretch, and what accounts that started before it still started with.
        var owed: [(account: AccountID, amount: Decimal, isFirst: Bool)] = []
        var takenOut: Decimal = 0
        var movedIn: Decimal = 0
        var movedOut: Decimal = 0
        var landed: Decimal = 0
        // The first day the cash and savings accounts' values in the stretch cover.
        var covered = from
        for account in report.accounts {
            if let record = firstRecordDate(of: account.account), record > from, record <= through {
                owed.append((account.account, account.change.other + account.change.saved, true))
            } else {
                saved[account.account] = account.change.saved
                let cash = moved(into: account, after: from, through: through)
                movedIn += cash?.amount ?? 0
                if let since = cash?.since { covered = min(covered, since) }
                if let cash, cash.isRecorded {
                    movedOut -= cash.amount
                } else if let kind = accounts[account.account]?.kind {
                    switch AccountGroup(kind: kind) {
                    case .debts:
                        // A card's purchases are spent, and a loan's money lands where it's paid out.
                        break
                    case .property:
                        // Sold, what it was worth left it, and its price landed in a cash account;
                        // a drop of one still held is lost value.
                        landed += max(account.change.saved, 0)
                        if account.change.end == 0 { movedOut += max(-account.change.saved, 0) }
                    case .pension:
                        takenOut += max(-account.change.saved, 0)
                    default:
                        takenOut += max(-account.change.saved, 0)
                        landed += max(account.change.saved, 0)
                    }
                }
            }
        }
        takenOut += max(movedOut - landed, 0)
        let paidIn = max(movedIn, 0)
        if covered < from, takenOut > 0 || paidIn > 0 {
            owed += stillStartedWith(after: covered, through: from, in: scope, among: report.accounts.map(\.account))
                .map { ($0.account, $0.amount, false) }
        }
        let assets = owed.reduce(Decimal(0)) { $0 + max($1.amount, 0) }
        let debts = owed.reduce(Decimal(0)) { $0 - min($1.amount, 0) }
        var startedWith: [AccountID: Decimal] = [:]
        for item in owed {
            let (offset, side) = item.amount > 0 ? (takenOut, assets) : (paidIn, debts)
            let share: Decimal = side == 0 ? 0 : min(offset / side, 1)
            let paid = item.amount * share
            saved[item.account, default: 0] += paid
            if item.isFirst {
                startedWith[item.account] = item.amount - paid
            } else if paid != 0 {
                startedWith[item.account] = -paid
            }
        }
        return SavedStretch(report: report, saved: saved, startedWith: startedWith)
    }

    /// What each of `candidates` whose records start after `from` through
    /// `through` still started with by `through`: its
    /// ``SavedStretch/startedWith`` over the stretches between the
    /// check-ins of those days, added up, leaving out those at zero.
    private func stillStartedWith(after from: CalendarDate, through: CalendarDate, in scope: NetWorthScope,
                                  among candidates: [AccountID]) -> [(account: AccountID, amount: Decimal)] {
        let started = candidates.filter { id in
            firstRecordDate(of: id).map { $0 > from && $0 <= through } ?? false
        }
        guard !started.isEmpty else { return [] }
        var total: [AccountID: Decimal] = [:]
        for stretch in savedStretches(between: savedCuts(after: from, through: through, in: scope), in: scope) {
            total.merge(stretch.startedWith, uniquingKeysWith: +)
        }
        return started.compactMap { id in total[id].flatMap { $0 == 0 ? nil : (id, $0) } }
    }

    /// What moved into a cash or savings account from your other accounts
    /// after `from` through `through` (negative: out of it), in the base
    /// currency: the sum of its valuations' ``moved(_:previous:)``, with
    /// `isRecorded` set. Where one of them doesn't record money in and out,
    /// what it saved over those days, as nothing tells a transfer apart.
    /// `since` is the date of its valuation before the first of them: the
    /// days they cover start after it. `nil` for other kinds.
    private func moved(into change: AccountChange, after from: CalendarDate, through: CalendarDate)
        -> (amount: Decimal, isRecorded: Bool, since: CalendarDate?)? {
        guard let account = accounts[change.account], account.kind.recordsMoneyInOut else { return nil }
        var total: Decimal? = 0
        var since: CalendarDate?
        var isFirst = true
        var previous: Valuation?
        for valuation in valuations(for: account.id) {
            defer { previous = valuation }
            guard valuation.date > from, valuation.date <= through else { continue }
            if isFirst {
                since = previous?.date
                isFirst = false
            }
            guard let sum = total, let moved = self.moved(valuation, previous: previous),
                  let inBase = fx.convert(moved, from: account.currency, to: baseCurrency, on: valuation.date)
            else {
                total = nil
                continue
            }
            total = sum + inBase
        }
        return (total ?? change.change.saved, total != nil, since)
    }
}
