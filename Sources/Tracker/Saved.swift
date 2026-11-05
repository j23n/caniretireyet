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
/// value made a check-in in between. When accounts' records start in
/// those days, they're paid for as one stretch over all of them would
/// pay for them, from what moved and landed over all of them, and this
/// stretch counts what that leaves after the stretches before it in
/// those days: so the days' numbers don't depend on the check-in in
/// between. What such an account owes is what it held at the end of the
/// stretch it starts in; what it saved after that is saved, as any
/// account's.
public struct SavedStretch: Hashable, Sendable {
    /// How each account changed over the stretch, after `report.from` through `report.to`.
    public let report: ChangeReport
    /// What each account that counted in the stretch saved.
    public let saved: [AccountID: Decimal]
    /// What each account whose records start in the stretch held when they
    /// start, as far as nothing tracked before paid for it; and the change
    /// in what an account that started in earlier days its values cover
    /// started with: below zero what money moved over those days pays for
    /// beyond what the stretches before it paid, above zero what they paid
    /// beyond it.
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
    /// then, as far as nothing tracked before paid for it, with the change
    /// in what accounts that started in earlier days its values cover
    /// started with (``startedWith``).
    public var totalStartedWith: Decimal {
        startedWith.keys.sorted().reduce(Decimal(0)) { $0 + (startedWith[$1] ?? 0) }
    }
}

extension Valuator {
    /// What the accounts in `scope` saved over each stretch between
    /// consecutive `cuts` (sorted dates, the first only where the first
    /// stretch starts), oldest first (``SavedStretch``).
    public func savedStretches(between cuts: [CalendarDate], in scope: NetWorthScope) -> [SavedStretch] {
        zip(cuts, cuts.dropFirst()).map { savedStretch(after: $0.0, through: $0.1, in: scope, cuts: cuts) }
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
    /// (``SavedStretch``), in a series cut at `cuts` as well as at
    /// check-ins, so that a stretch whose cash values cover days before it
    /// takes off what the series' own stretches of those days counted.
    func savedStretch(after from: CalendarDate, through: CalendarDate, in scope: NetWorthScope,
                      cuts: [CalendarDate] = []) -> SavedStretch {
        let report = change(from: from, to: through, in: scope)
        var saved: [AccountID: Decimal] = [:]
        // The amounts money moved may pay for: the first amounts of the accounts whose records
        // start in the stretch.
        var owed: [(account: AccountID, amount: Decimal)] = []
        var tracked: [(change: AccountChange, after: CalendarDate)] = []
        for account in report.accounts {
            if let record = firstRecordDate(of: account.account), record > from, record <= through {
                owed.append((account.account, account.change.other + account.change.saved))
            } else {
                saved[account.account] = account.change.saved
                tracked.append((account, from))
            }
        }
        let offsets = self.offsets(tracked, through: through)
        if let covered = offsets.covered, covered < from, startsAfter(covered, through: through, in: scope) {
            return savedStretch(after: from, through: through, in: scope, report: report, from: covered,
                                cuts: cuts)
        }
        var startedWith: [AccountID: Decimal] = [:]
        for item in pay(owed, offsets) {
            saved[item.account, default: 0] += item.paid
            startedWith[item.account] = item.startedWith
        }
        return SavedStretch(report: report, saved: saved, startedWith: startedWith)
    }

    /// What money moved after each change's `after` through `through` can
    /// pay for first amounts with (``SavedStretch``): the money taken out of
    /// the accounts tracked before (`takenOut`) for an asset's, and moved
    /// into their cash and savings accounts (`paidIn`) for a debt's; and
    /// the first day the cash and savings values among them cover, when
    /// one is earlier than its `after`.
    private func offsets(_ tracked: [(change: AccountChange, after: CalendarDate)], through: CalendarDate)
        -> (takenOut: Decimal, paidIn: Decimal, covered: CalendarDate?) {
        var takenOut: Decimal = 0
        var movedIn: Decimal = 0
        var movedOut: Decimal = 0
        var landed: Decimal = 0
        var covered: CalendarDate?
        for (account, from) in tracked {
            let cash = moved(into: account, after: from, through: through)
            movedIn += cash?.amount ?? 0
            if let since = cash?.since, since < from { covered = min(covered ?? since, since) }
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
        takenOut += max(movedOut - landed, 0)
        return (takenOut, max(movedIn, 0), covered)
    }

    /// What `offsets` pay of each first amount in `owed`, each side's
    /// offset shared over that side's amounts in proportion to them, and
    /// what's left of each, what it started with.
    private func pay(_ owed: [(account: AccountID, amount: Decimal)],
                     _ offsets: (takenOut: Decimal, paidIn: Decimal, covered: CalendarDate?))
        -> [(account: AccountID, paid: Decimal, startedWith: Decimal)] {
        let assets = owed.reduce(Decimal(0)) { $0 + max($1.amount, 0) }
        let debts = owed.reduce(Decimal(0)) { $0 - min($1.amount, 0) }
        return owed.map { item in
            let (offset, side) = item.amount > 0 ? (offsets.takenOut, assets) : (offsets.paidIn, debts)
            let share: Decimal = side == 0 ? 0 : min(offset / side, 1)
            let paid = item.amount * share
            return (item.account, paid, item.amount - paid)
        }
    }

    /// Whether an account in `scope` has its first record after `from`
    /// through `through`.
    private func startsAfter(_ from: CalendarDate, through: CalendarDate, in scope: NetWorthScope) -> Bool {
        accounts.values.contains { account in
            scope.includes(account) && (firstRecordDate(of: account.id).map { $0 > from && $0 <= through } ?? false)
        }
    }

    /// The stretch after `from` through `through` (`report`), when the
    /// values in it cover days from `covered` on and accounts' records
    /// start in those days. The days are worked out as one stretch: an
    /// account whose records start in them owes what it held at the end
    /// of the stretch it starts in, cut at the check-ins and `cuts`
    /// between, and what it saved after that counts as any account's
    /// tracked before does. Each such account then started with what
    /// that leaves, less what the stretches before `from` said it started
    /// with, and saved what it saved here, less that. Every other
    /// account saved what its change counts as saved.
    private func savedStretch(after from: CalendarDate, through: CalendarDate, in scope: NetWorthScope,
                              report: ChangeReport, from covered: CalendarDate, cuts: [CalendarDate])
        -> SavedStretch {
        let between = savedCuts(after: covered, through: from, in: scope,
                                adding: cuts.filter { $0 > covered && $0 < from })
        let all = Set(cuts + between).sorted()
        let before = zip(between, between.dropFirst()).map {
            savedStretch(after: $0.0, through: $0.1, in: scope, cuts: all)
        }
        let ends = Array(between.dropFirst()) + [through]
        var owed: [(account: AccountID, amount: Decimal)] = []
        var tracked: [(change: AccountChange, after: CalendarDate)] = []
        for account in accounts.values.sorted(by: { $0.id < $1.id })
        where scope.includes(account) && account.isOpen(onAnyDayFrom: covered, through: through) {
            guard let record = firstRecordDate(of: account.id), record > covered, record <= through else {
                tracked.append((change(of: account, from: covered, to: through), covered))
                continue
            }
            let end = ends.first { $0 >= record } ?? through
            let first = change(of: account, from: covered, to: end)
            owed.append((account.id, first.change.other + first.change.saved))
            if end < through { tracked.append((change(of: account, from: end, to: through), end)) }
        }
        let whole = Dictionary(pay(owed, offsets(tracked, through: through)).map { ($0.account, $0.startedWith) },
                               uniquingKeysWith: +)
        var saved: [AccountID: Decimal] = [:]
        var startedWith: [AccountID: Decimal] = [:]
        for account in report.accounts {
            let id = account.account
            guard let wholeStartedWith = whole[id] else {
                saved[id] = account.change.saved
                continue
            }
            let left = before.reduce(wholeStartedWith) { $0 - ($1.startedWith[id] ?? 0) }
            let startsHere = firstRecordDate(of: id).map { $0 > from } ?? false
            saved[id] = (startsHere ? account.change.other : 0) + account.change.saved - left
            if left != 0 || startsHere { startedWith[id] = left }
        }
        return SavedStretch(report: report, saved: saved, startedWith: startedWith)
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
