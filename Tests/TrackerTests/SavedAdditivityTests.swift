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
/// cuts fall can matter.
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
        #expect(same(moved[0].oneOffs, moved[1].oneOffs + moved[2].oneOffs), "\(window)",
                sourceLocation: sourceLocation)
        #expect(same(moved[0].startedWith, moved[1].startedWith + moved[2].startedWith), "\(window)",
                sourceLocation: sourceLocation)
        #expect(same(moved[0].change, moved[1].change + moved[2].change), "\(window)", sourceLocation: sourceLocation)
        // Pay, where money in and out was recorded on both sides of the cut.
        if let pay = moved[0].pay, let first = moved[1].pay, let second = moved[2].pay {
            #expect(same(pay.moneyIn, first.moneyIn + second.moneyIn), "\(window)", sourceLocation: sourceLocation)
            #expect(same(pay.tax, first.tax + second.tax), "\(window)", sourceLocation: sourceLocation)
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

    /// The broker's first record, a deposit of 10 February, is paid for by
    /// what moved out of the bank by 28 February, but not by the bank's
    /// 31 January. Cut on 15 February, the stretch it starts in ends
    /// before the bank's value, which records the transfer, so through
    /// the 15th it started with the deposit; the bank's value, which covers
    /// the days since 31 January, then pays for it (PROGRESS.md, "Saved").
    /// So the two stretches add up to the whole.
    @Test func aCutInANewAccountsStretchPaysForItAtTheNextValue() throws {
        let valuator = Valuator(library: try InvariantLibrary.newAccount.library())
        let whole = valuator.savedStretches(between: ["2026-01-31", "2026-02-28"], in: .netWorth)
        let cut = valuator.savedStretches(between: ["2026-01-31", "2026-02-15", "2026-02-28"], in: .netWorth)
        #expect(whole.map(\.totalStartedWith) == [0])
        #expect(cut.map(\.totalStartedWith) == [1000, -1000])
        #expect(whole.map(\.total).sum == cut.map(\.total).sum)
    }

    /// A current account valued on 31 January and 28 February, a broker
    /// tracked since January, and a savings account first valued on
    /// 15 February with 6,000 from outside: `savings` the library with
    /// that value, which makes a check-in in the middle of the month.
    private func monthWithANewSavingsAccount(pot: Bool = false, midMonth: Bool) -> Library {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        var accounts = [
            Account(id: "current", name: "Current", kind: .cash, currency: .eur, opened: "2026-01-01"),
            Account(id: "savings", name: "Savings", kind: .savings, currency: .eur, opened: "2026-02-01"),
        ]
        if pot {
            accounts.append(Account(id: "pot", name: "Pot", kind: .cash, currency: .eur, opened: "2026-01-01"))
        } else {
            accounts.append(Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                    opened: "2026-01-01", valuation: .trades))
        }
        for account in accounts { library.accounts[account.id] = account }
        library.upsert(Valuation(account: "current", date: "2026-01-31", balance: 10000))
        if pot {
            // A pot without money in and out, drawn down before the 15th and filled up again after it.
            library.upsert(Valuation(account: "current", date: "2026-02-28", balance: 10000, moneyIn: 0,
                                     moneyOut: 0))
            library.upsert(Valuation(account: "pot", date: "2026-01-31", balance: 10000))
            library.upsert(Valuation(account: "pot", date: "2026-02-15", balance: 4000))
            library.upsert(Valuation(account: "pot", date: "2026-02-28", balance: 10000))
        } else {
            // 5,000 moved to the broker on 10 February.
            library.upsert(Valuation(account: "current", date: "2026-02-28", balance: 5000, moneyIn: 0,
                                     moneyOut: 0))
            library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 0, saved: 0))
            library.upsert(Trade(account: "broker", date: "2026-02-10", id: "dep", type: .deposit, amount: 5000))
        }
        if midMonth {
            library.upsert(Valuation(account: "savings", date: "2026-02-15", balance: 6000))
            library.upsert(Valuation(account: "savings", date: "2026-02-28", balance: 6000, moneyIn: 0, moneyOut: 0))
        } else {
            library.upsert(Valuation(account: "savings", date: "2026-02-28", balance: 6000))
        }
        return library
    }

    /// The 5,000 moved to the broker already counts as saved there before
    /// the 15th, so the current account's value on the 28th, which records
    /// it leaving, doesn't pay for the savings account too: February saved
    /// nothing, with and without the value on the 15th.
    @Test func moneySavedBeforeTheCheckInDoesntPayForANewAccountAgain() throws {
        for midMonth in [false, true] {
            let valuator = Valuator(library: monthWithANewSavingsAccount(midMonth: midMonth))
            let moved = valuator.whatMoved(valuator.change(from: "2026-01-31", to: "2026-02-28"))
            #expect(moved.saved == 0, "\(midMonth)")
            #expect(moved.startedWith == 6000, "\(midMonth)")
            #expect(moved.unexplained == 0, "\(midMonth)")
        }
        let valuator = Valuator(library: monthWithANewSavingsAccount(midMonth: true))
        let stretches = valuator.savedStretches(between: ["2026-01-31", "2026-02-15", "2026-02-28"], in: .netWorth)
        #expect(stretches.map(\.saved) == [["current": 0, "broker": 5000, "savings": 0],
                                            ["current": -5000, "broker": 0, "savings": 0]])
        #expect(stretches.map(\.startedWith) == [["savings": 6000], [:]])
    }

    /// What was drawn from the pot before the 15th pays for the savings
    /// account there; filled up again after it, over all of February the
    /// pot paid for nothing. So
    /// the stretch after the 15th takes back what the one before paid:
    /// February started with 6,000, with and without the value on the 15th.
    @Test func aStretchTakesBackWhatTheOneBeforePaidForANewAccount() throws {
        for midMonth in [false, true] {
            let valuator = Valuator(library: monthWithANewSavingsAccount(pot: true, midMonth: midMonth))
            let moved = valuator.whatMoved(valuator.change(from: "2026-01-31", to: "2026-02-28"))
            #expect(moved.saved == 0, "\(midMonth)")
            #expect(moved.startedWith == 6000, "\(midMonth)")
        }
        let valuator = Valuator(library: monthWithANewSavingsAccount(pot: true, midMonth: true))
        let stretches = valuator.savedStretches(between: ["2026-01-31", "2026-02-15", "2026-02-28"], in: .netWorth)
        #expect(stretches.map(\.saved) == [["current": 0, "pot": -6000, "savings": 6000],
                                            ["current": 0, "pot": 6000, "savings": -6000]])
        #expect(stretches.map(\.startedWith) == [["savings": 0], ["savings": 6000]])
    }

    /// A savings account valued once a quarter covers the days back to
    /// 31 December, when a pension fund's records start in January. What
    /// the fund saved after its first value, its contributions, is saved in
    /// the month it's saved in, and only its first value is started with.
    @Test func aNewAccountsSavingAfterItsFirstValueStaysSaved() throws {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        let accounts = [
            Account(id: "current", name: "Current", kind: .cash, currency: .eur, opened: "2025-12-01"),
            Account(id: "rainy", name: "Rainy day", kind: .savings, currency: .eur, opened: "2025-12-01"),
            Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur, opened: "2026-01-01"),
        ]
        for account in accounts { library.accounts[account.id] = account }
        library.upsert(Valuation(account: "rainy", date: "2025-12-31", balance: 10000))
        library.upsert(Valuation(account: "rainy", date: "2026-03-31", balance: 10000, moneyIn: 0, moneyOut: 0))
        library.upsert(Valuation(account: "current", date: "2025-12-31", balance: 5000))
        for date: CalendarDate in ["2026-01-31", "2026-02-28", "2026-03-31"] {
            library.upsert(Valuation(account: "current", date: date, balance: 5000, moneyIn: 0, moneyOut: 0))
        }
        library.upsert(Valuation(account: "pension", date: "2026-01-31", balance: 20000))
        library.upsert(Valuation(account: "pension", date: "2026-02-28", balance: 20500, saved: 500))
        library.upsert(Valuation(account: "pension", date: "2026-03-31", balance: 21000, saved: 500))
        let valuator = Valuator(library: library)
        let stretches = valuator.savedStretches(
            between: ["2025-12-31", "2026-01-31", "2026-02-28", "2026-03-31"], in: .netWorth)
        #expect(stretches.map { $0.saved["pension"] } == [0, 500, 500])
        #expect(stretches.map(\.startedWith) == [["pension": 20000], [:], [:]])
    }
}
