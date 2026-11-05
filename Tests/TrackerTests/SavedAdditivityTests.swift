import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B3: what was saved adds up over time. For a check-in `b`
/// between `a` and `c`, what was saved after `a` through `c` is what was
/// saved through `b` and after it, account by account. A cut that isn't a
/// check-in splits what was saved the same way, as long as no account's
/// records start in the days: a new account's first amount is shared out
/// by what moved in its stretch (PROGRESS.md, "Saved"), so there where the
/// cuts fall matters.
struct SavedAdditivityTests {
    /// `saved(a, c)` against `saved(a, b) + saved(b, c)`, and what moved net
    /// worth and the Overview's split over the same days.
    private func expectAdditive(_ valuator: Valuator, _ a: CalendarDate, _ b: CalendarDate, _ c: CalendarDate,
                                sourceLocation: SourceLocation = #_sourceLocation) {
        let window = "\(a) | \(b) | \(c)"
        let whole = valuator.saved(after: a, through: c).byAccount
        let parts = valuator.saved(after: a, through: b).byAccount
            .adding(valuator.saved(after: b, through: c).byAccount)
        #expect(Set(whole.withoutZeros.keys) == Set(parts.withoutZeros.keys), "\(window)",
                sourceLocation: sourceLocation)
        for (account, saved) in whole {
            #expect(same(saved, parts[account] ?? 0), "\(account) \(window)", sourceLocation: sourceLocation)
        }

        let moved = [(a, c), (a, b), (b, c)].map { valuator.whatMoved(valuator.change(from: $0.0, to: $0.1)) }
        #expect(same(moved[0].saved, moved[1].saved + moved[2].saved), "\(window)", sourceLocation: sourceLocation)
        #expect(same(moved[0].markets, moved[1].markets + moved[2].markets), "\(window)",
                sourceLocation: sourceLocation)
        #expect(same(moved[0].startedWith, moved[1].startedWith + moved[2].startedWith), "\(window)",
                sourceLocation: sourceLocation)
        #expect(same(moved[0].change, moved[1].change + moved[2].change), "\(window)", sourceLocation: sourceLocation)
        // Pay, where money in and out was recorded on both sides of the cut.
        if let pay = moved[0].pay, let first = moved[1].pay, let second = moved[2].pay {
            #expect(same(pay.moneyIn, first.moneyIn + second.moneyIn), "\(window)", sourceLocation: sourceLocation)
            #expect(same(pay.tax, first.tax + second.tax), "\(window)", sourceLocation: sourceLocation)
            #expect(same(pay.oneOffs, first.oneOffs + second.oneOffs), "\(window)", sourceLocation: sourceLocation)
            // Each pension's contributions are at least zero in every window,
            // so the parts can only add up to more.
            #expect(pay.pension <= first.pension + second.pension, "\(window)", sourceLocation: sourceLocation)
        }
        let split = [(a, c), (a, b), (b, c)].map { valuator.savedSplit(of: valuator.change(from: $0.0, to: $0.1)) }
        #expect(same(split[0].saved, split[1].saved + split[2].saved), "\(window)", sourceLocation: sourceLocation)
        #expect(same(split[0].market, split[1].market + split[2].market), "\(window)", sourceLocation: sourceLocation)
    }

    @Test(arguments: InvariantLibrary.allCases)
    func savedAddsUpOverACheckIn(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        let dates = Windows.checkIns(valuator)
        for index in dates.indices.dropFirst().dropLast() {
            expectAdditive(valuator, dates[index - 1], dates[index], dates[index + 1])
            if let first = dates.first, let last = dates.last {
                expectAdditive(valuator, first, dates[index], last)
            }
        }
    }

    @Test(arguments: InvariantLibrary.allCases)
    func savedAddsUpOverADayThatIsntACheckIn(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        var checked = 0
        for (from, to) in Windows.consecutive(valuator) where from.days(to: to) > 1 {
            guard !Windows.anAccountStarts(valuator, after: from, through: to) else { continue }
            expectAdditive(valuator, from, from.adding(days: from.days(to: to) / 2), to)
            checked += 1
        }
        #expect(checked > 0)
    }

    /// Where the cuts fall decides what a new account started with: the
    /// broker's first record, a deposit of 10 February, is paid for by
    /// what moved out of the bank by 28 February, but not by the bank's
    /// 31 January. Cut on 15 February, the stretch it starts in ends
    /// before the bank's value, which records the transfer, so it started
    /// with the deposit. That's the rule as PROGRESS.md states it, so this
    /// pins it rather than asserting it adds up.
    @Test func aCutInANewAccountsStretchMovesWhatItStartedWith() throws {
        let valuator = Valuator(library: try InvariantLibrary.newAccount.library())
        let whole = valuator.savedStretches(between: ["2026-01-31", "2026-02-28"], in: .netWorth)
        let cut = valuator.savedStretches(between: ["2026-01-31", "2026-02-15", "2026-02-28"], in: .netWorth)
        #expect(whole.map(\.totalStartedWith) == [0])
        #expect(cut.map(\.totalStartedWith) == [1000, 0])
        #expect(whole.map(\.total).sum == cut.map(\.total).sum + 1000)
    }
}
